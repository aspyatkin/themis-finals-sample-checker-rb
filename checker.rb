require 'themis/checker'


class SampleChecker < Themis::Checker::Server
    def push(endpoint, flag_id, flag)
        sleep Random.new.rand 1..5
	   return Themis::Checker::Result::UP, flag_id
    end

    def pull(endpoint, flag_id, flag)
        sleep Random.new.rand 1..5
        Themis::Checker::Result::UP
    end
end


checker = SampleChecker.new
checker.run
