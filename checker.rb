require 'themis/finals/checker/result'

def push(endpoint, flag, adjunct, metadata)
  sleep ::Random.new.rand 1..5
  return ::Themis::Finals::Checker::Result::UP, adjunct
end

def pull(endpoint, flag, adjunct, metadata)
  sleep ::Random.new.rand 1..5
  return ::Themis::Finals::Checker::Result::UP
end
