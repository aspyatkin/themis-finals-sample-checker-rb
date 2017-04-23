require 'themis/finals/checker/result'

def get_random_message
  range = [*'0'..'9',*'A'..'Z',*'a'..'z']
  Array.new(16){ range.sample }.join
end

def push(endpoint, capsule, label, metadata)
  sleep ::Random.new.rand 1..5
  return ::Themis::Finals::Checker::Result::UP, label, get_random_message
end

def pull(endpoint, capsule, label, metadata)
  sleep ::Random.new.rand 1..5
  return ::Themis::Finals::Checker::Result::UP, get_random_message
end
