require 'securerandom'
require 'themis/finals/checker/result'
require './utils'

$logger = get_logger

def get_random_message
  range = [*'0'..'9',*'A'..'Z',*'a'..'z']
  Array.new(16){ range.sample }.join
end

def push(endpoint, capsule, label, metadata)
  $logger.debug('PUSH capsule: ' + capsule)
  sleep ::Random.new.rand(1..5)
  new_label = ::SecureRandom.uuid
  return ::Themis::Finals::Checker::Result::UP, new_label, get_random_message
end

def pull(endpoint, capsule, label, metadata)
  $logger.debug('PULL capsule: ' + capsule)
  sleep ::Random.new.rand(1..5)
  return ::Themis::Finals::Checker::Result::UP, get_random_message
end
