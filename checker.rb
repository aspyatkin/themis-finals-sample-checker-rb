require 'femida_checker'


class SampleChecker < FemidaChecker::Base
    protected
    def _push(endpoint, flag_id, flag)
        sleep Random.new.rand 1..5
	return FemidaChecker::Result::OK, ''
    end

    def _pull(endpoint, flag_id, flag)
        sleep Random.new.rand 1..5
        FemidaChecker::Result::OK
    end
end


checker = SampleChecker.new
checker.run

