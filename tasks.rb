require 'sidekiq'
require 'themis/finals/checker/result'
require 'time_difference'
require 'net/http'
require 'json'

::Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://127.0.0.1:6379/10' }

  config.on(:startup) do
    puts "Starting queue process, instance #{ENV['QUEUE_INSTANCE']}"
  end
  config.on(:quiet) do
    puts 'Got USR1, stopping further job processing...'
  end
  config.on(:shutdown) do
    puts 'Got TERM, shutting down process...'
  end
end

::Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://127.0.0.1:6379/10' }
end

class Push
  include ::Sidekiq::Worker

  def push(endpoint, flag, adjunct, metadata)
    sleep ::Random.new.rand 1..5
    return ::Themis::Finals::Checker::Result::UP, adjunct
  end

  def internal_push(endpoint, flag, adjunct, metadata)
    result, updated_adjunct = ::Themis::Finals::Checker::Result::INTERNAL_ERROR, adjunct
    begin
      result, updated_adjunct = push endpoint, flag, adjunct, metadata
    rescue Interrupt
      raise
    rescue Exception => e
      puts e.message
      e.backtrace.each { |line| puts line }
    end

    return result, updated_adjunct
  end

  def perform(job_data)
    metadata = job_data['metadata']
    timestamp_created = ::DateTime.iso8601 metadata['timestamp']
    timestamp_delivered = ::DateTime.now

    status, updated_adjunct = internal_push(
      job_data['endpoint'],
      job_data['flag'],
      ::Base64.decode64(job_data['adjunct']),
      metadata
    )

    timestamp_processed = ::DateTime.now

    job_result = {
      status: status,
      flag: job_data['flag'],
      adjunct: ::Base64.encode64(updated_adjunct)
    }

    delivery_time = ::TimeDifference.between(timestamp_created, timestamp_delivered).in_seconds
    processing_time = ::TimeDifference.between(timestamp_delivered, timestamp_processed).in_seconds

    log_message = 'PUSH flag `%s` /%d to `%s`@`%s` (%s) - status %s, adjunct `%s` [delivery %.2fs, processing %.2fs]' % [
      job_data['flag'],
      metadata['round'],
      metadata['service_name'],
      metadata['team_name'],
      job_data['endpoint'],
      ::Themis::Finals::Checker::Result.key(status),
      job_result[:adjunct],
      delivery_time,
      processing_time
    ]

    puts log_message

    uri = URI("http://master.finals.themis-project.com/api/report_push")

    req = ::Net::HTTP::Post.new(uri)
    req.body = job_result.to_json
    req.content_type = 'application/json'

    res = ::Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    puts res.value
  end
end

class Pull
  include ::Sidekiq::Worker

  def pull(endpoint, flag, adjunct, metadata)
    sleep ::Random.new.rand 1..5
    return ::Themis::Finals::Checker::Result::UP
  end

  def internal_pull(endpoint, flag, adjunct, metadata)
    result = ::Themis::Finals::Checker::Result::INTERNAL_ERROR
    begin
      result = pull endpoint, flag, adjunct, metadata
    rescue Interrupt
      raise
    rescue Exception => e
      puts e.message
      e.backtrace.each { |line| puts line }
    end

    result
  end

  def perform(job_data)
    metadata = job_data['metadata']
    timestamp_created = ::DateTime.iso8601 metadata['timestamp']
    timestamp_delivered = ::DateTime.now

    status = internal_pull(
      job_data['endpoint'],
      job_data['flag'],
      ::Base64.decode64(job_data['adjunct']),
      job_data['metadata']
    )

    timestamp_processed = ::DateTime.now

    job_result = {
      request_id: job_data['request_id'],
      status: status
    }

    delivery_time = ::TimeDifference.between(timestamp_created, timestamp_delivered).in_seconds
    processing_time = ::TimeDifference.between(timestamp_delivered, timestamp_processed).in_seconds

    log_message = 'PULL flag `%s` /%d from `%s`@`%s` (%s) with adjunct `%s` - status %s [delivery %.2fs, processing %.2fs]' % [
      job_data['flag'],
      metadata['round'],
      metadata['service_name'],
      metadata['team_name'],
      job_data['endpoint'],
      job_data['adjunct'],
      ::Themis::Finals::Checker::Result.key(status),
      delivery_time,
      processing_time
    ]

    puts log_message

    uri = URI("http://master.finals.themis-project.com/api/report_pull")

    req = ::Net::HTTP::Post.new(uri)
    req.body = job_result.to_json
    req.content_type = 'application/json'

    res = ::Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    puts res.value
  end
end
