require 'logger'
require 'securerandom'
require 'base64'
require 'digest/sha2'

def get_logger
  logger = ::Logger.new STDOUT

  # Setup log formatter
  logger.datetime_format = '%Y-%m-%d %H:%M:%S'
  logger.formatter = proc do |severity, datetime, progname, msg|
    "[#{datetime}] #{severity} -- #{msg}\n"
  end

  $stdout.sync = ENV['STDOUT_SYNC'] == 'true'

  # Setup log level
  case ENV['LOG_LEVEL']
  when 'DEBUG'
    logger.level = ::Logger::DEBUG
  when 'INFO'
    logger.level = ::Logger::INFO
  when 'WARN'
    logger.level = ::Logger::WARN
  when 'ERROR'
    logger.level = ::Logger::ERROR
  when 'FATAL'
    logger.level = ::Logger::FATAL
  when 'UNKNOWN'
    logger.level = ::Logger::UNKNOWN
  else
    logger.level = ::Logger::INFO
  end
  logger
end

def issue_token(name)
  nonce_size = ENV.fetch('THEMIS_FINALS_NONCE_SIZE', '16').to_i

  nonce = ::SecureRandom.random_bytes nonce_size
  secret_key = ::Base64.urlsafe_decode64 ENV["THEMIS_FINALS_#{name}_KEY"]

  hash = ::Digest::SHA256.new
  hash << nonce
  hash << secret_key

  nonce_bytes = nonce.bytes
  digest_bytes = hash.digest.bytes

  token_bytes = nonce_bytes + digest_bytes
  ::Base64.urlsafe_encode64 token_bytes.pack 'c*'
end

def issue_checker_token
  issue_token 'CHECKER'
end

def verify_token(name, token)
  return false if token.nil?

  begin
    token_bytes = ::Base64.urlsafe_decode64(token).bytes
  rescue
    return false
  end

  nonce_size = ENV.fetch('THEMIS_FINALS_NONCE_SIZE', '16').to_i

  return false if token_bytes.size != 32 + nonce_size

  nonce = token_bytes[0...nonce_size].pack 'c*'
  received_digest_bytes = token_bytes[nonce_size..-1]

  secret_key = ::Base64.urlsafe_decode64 ENV["THEMIS_FINALS_#{name}_KEY"]

  hash = ::Digest::SHA256.new
  hash << nonce
  hash << secret_key

  digest_bytes = hash.digest.bytes

  return digest_bytes == received_digest_bytes
end

def verify_master_token(token)
  verify_token 'MASTER', token
end
