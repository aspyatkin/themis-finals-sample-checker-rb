require 'sidekiq'
require 'themis/finals/checker/result'
require 'time_difference'
require 'net/http'
require 'json'
require './utils'
require 'raven/base'
require 'jwt'
require 'openssl'

config_module_name = ENV['THEMIS_FINALS_CHECKER_MODULE'] || ::File.join(
  Dir.pwd,
  'checker.rb'
)
require config_module_name

$logger = get_logger

::Sidekiq.default_worker_options = { 'retry' => 0 }

::Sidekiq.configure_server do |config|
  config.redis = {
    url: "redis://#{ENV['REDIS_HOST']}:#{ENV['REDIS_PORT']}/#{ENV['REDIS_DB']}"
  }

  config.on(:startup) do
    $logger.info "Starting queue process, instance #{ENV['QUEUE_INSTANCE']}"
  end
  config.on(:quiet) do
    $logger.info 'Got USR1, stopping further job processing...'
  end
  config.on(:shutdown) do
    $logger.info 'Got TERM, shutting down process...'
  end
end

::Sidekiq.configure_client do |config|
  config.redis = {
    url: "redis://#{ENV['REDIS_HOST']}:#{ENV['REDIS_PORT']}/#{ENV['REDIS_DB']}"
  }
end

$raven_enabled = !ENV['SENTRY_DSN'].nil?

if $raven_enabled
  ::Raven.configure do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.ssl_verification = false
    config.logger = $logger
    config.async = lambda { |event|
      ::Thread.new { ::Raven.send_event(event) }
    }
  end
end

def decode_capsule(capsule)
  wrap_prefix = ::ENV['THEMIS_FINALS_FLAG_WRAP_PREFIX']
  wrap_suffix = ::ENV['THEMIS_FINALS_FLAG_WRAP_SUFFIX']
  encoded_payload = capsule.slice(
    wrap_prefix.length,
    capsule.length - wrap_prefix.length - wrap_suffix.length
  )

  key = ::OpenSSL::PKey.read(::ENV['THEMIS_FINALS_FLAG_SIGN_KEY_PUBLIC'].gsub('\n', "\n"))
  alg = 'none'
  if key.class == ::OpenSSL::PKey::RSA
    alg = 'RS256'
  elsif key.class == ::OpenSSL::PKey::EC
    alg = 'ES256'
  end

  payload = ::JWT.decode(encoded_payload, key, true, { algorithm: alg })
  payload[0]['flag']
end

class Push
  include ::Sidekiq::Worker

  def internal_push(endpoint, capsule, label, metadata)
    result = ::Themis::Finals::Checker::Result::INTERNAL_ERROR
    updated_label = label
    begin
      result, updated_label, message = push(endpoint, capsule, label, metadata)
    rescue Interrupt
      raise
    rescue Exception => e
      if $raven_enabled
        ::Raven.capture_exception e
      end
      $logger.error e.message
      e.backtrace.each { |line| $logger.error line }
    end

    return result, updated_label, message
  end

  def perform(job_data)
    params = job_data['params']
    metadata = job_data['metadata']
    timestamp_created = ::DateTime.iso8601 metadata['timestamp']
    timestamp_delivered = ::DateTime.now

    flag = decode_capsule(params['capsule'])

    status, updated_label, message = internal_push(
      params['endpoint'],
      params['capsule'],
      ::Base64.urlsafe_decode64(params['label']),
      metadata
    )

    timestamp_processed = ::DateTime.now

    job_result = {
      status: status,
      flag: flag,
      label: ::Base64.urlsafe_encode64(updated_label),
      message: message
    }

    delivery_time = ::TimeDifference.between(
      timestamp_created,
      timestamp_delivered
    ).in_seconds
    processing_time = ::TimeDifference.between(
      timestamp_delivered,
      timestamp_processed
    ).in_seconds

    log_message = \
      'PUSH flag `%s` /%d to `%s`@`%s` (%s) - status %s, label `%s` '\
      '[delivery %.2fs, processing %.2fs]' % [
        flag,
        metadata['round'],
        metadata['service_name'],
        metadata['team_name'],
        params['endpoint'],
        ::Themis::Finals::Checker::Result.key(status),
        job_result[:label],
        delivery_time,
        processing_time
      ]

    if $raven_enabled
      short_log_message = \
        'PUSH `%s...` /%d to `%s` - status %s' % [
          flag[0..7],
          metadata['round'],
          metadata['team_name'],
          ::Themis::Finals::Checker::Result.key(status)
        ]

      raven_data = {
        level: 'info',
        tags: {
          tf_operation: 'push',
          tf_status: ::Themis::Finals::Checker::Result.key(status).to_s,
          tf_team: metadata['team_name'],
          tf_service: metadata['service_name'],
          tf_round: metadata['round']
        },
        extra: {
          endpoint: params['endpoint'],
          capsule: params['capsule'],
          flag: flag,
          label: job_result[:label],
          message: job_result[:message],
          delivery_time: delivery_time,
          processing_time: processing_time
        }
      }

      ::Raven.capture_message short_log_message, raven_data
    end

    $logger.info log_message

    uri = URI(job_data['report_url'])

    req = ::Net::HTTP::Post.new(uri)
    req.body = job_result.to_json
    req.content_type = 'application/json'
    req[ENV['THEMIS_FINALS_AUTH_TOKEN_HEADER']] = issue_checker_token

    res = ::Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    unless res.is_a?(::Net::HTTPSuccess)
      $logger.error res.code
      $logger.error res.message
    end
  end
end

class Pull
  include ::Sidekiq::Worker

  def internal_pull(endpoint, capsule, label, metadata)
    result = ::Themis::Finals::Checker::Result::INTERNAL_ERROR
    begin
      result, message = pull(endpoint, capsule, label, metadata)
    rescue Interrupt
      raise
    rescue Exception => e
      if $raven_enabled
        ::Raven.capture_exception e
      end
      $logger.error e.message
      e.backtrace.each { |line| $logger.error line }
    end

    return result, message
  end

  def perform(job_data)
    params = job_data['params']
    metadata = job_data['metadata']
    timestamp_created = ::DateTime.iso8601 metadata['timestamp']
    timestamp_delivered = ::DateTime.now

    flag = decode_capsule(params['capsule'])

    status, message = internal_pull(
      params['endpoint'],
      params['capsule'],
      ::Base64.urlsafe_decode64(params['label']),
      metadata
    )

    timestamp_processed = ::DateTime.now

    job_result = {
      request_id: params['request_id'],
      status: status,
      message: message
    }

    delivery_time = ::TimeDifference.between(
      timestamp_created,
      timestamp_delivered
    ).in_seconds
    processing_time = ::TimeDifference.between(
      timestamp_delivered,
      timestamp_processed
    ).in_seconds

    log_message = \
      'PULL flag `%s` /%d from `%s`@`%s` (%s) with label `%s` - status %s '\
      '[delivery %.2fs, processing %.2fs]' % [
        flag,
        metadata['round'],
        metadata['service_name'],
        metadata['team_name'],
        params['endpoint'],
        params['label'],
        ::Themis::Finals::Checker::Result.key(status),
        delivery_time,
        processing_time
      ]

    if $raven_enabled
      short_log_message = \
        'PULL `%s...` /%d from `%s` - status %s' % [
          flag[0..7],
          metadata['round'],
          metadata['team_name'],
          ::Themis::Finals::Checker::Result.key(status)
        ]

      raven_data = {
        level: 'info',
        tags: {
          tf_operation: 'pull',
          tf_status: ::Themis::Finals::Checker::Result.key(status).to_s,
          tf_team: metadata['team_name'],
          tf_service: metadata['service_name'],
          tf_round: metadata['round']
        },
        extra: {
          endpoint: params['endpoint'],
          capsule: params['capsule'],
          flag: flag,
          label: params['label'],
          message: job_result[:message],
          delivery_time: delivery_time,
          processing_time: processing_time
        }
      }

      ::Raven.capture_message short_log_message, raven_data
    end

    $logger.info log_message

    uri = URI(job_data['report_url'])

    req = ::Net::HTTP::Post.new(uri)
    req.body = job_result.to_json
    req.content_type = 'application/json'
    req[ENV['THEMIS_FINALS_AUTH_TOKEN_HEADER']] = issue_checker_token

    res = ::Net::HTTP.start(uri.hostname, uri.port) do |http|
      http.request(req)
    end

    unless res.is_a?(::Net::HTTPSuccess)
      $logger.error res.code
      $logger.error res.message
    end
  end
end
