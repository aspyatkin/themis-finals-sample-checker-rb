require 'themis/checker/result'
require 'themis/checker/server'


class SampleChecker < Themis::Checker::Server
    def push(endpoint, flag, adjunct, metadata)
        sleep Random.new.rand 1..5
	   return Themis::Checker::Result::UP, adjunct
    end

    def pull(endpoint, flag, adjunct, metadata)
        sleep Random.new.rand 1..5
        Themis::Checker::Result::UP
    end
end


checker = SampleChecker.new
checker.run
