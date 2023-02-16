require "spec_helper"

RSpec.describe RSpec::Abq::Formatter do
  describe ".abq_result(example)" do
    it "reports times in microseconds", :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      started_at_string = "2023-01-01T01:01:01.123456Z"
      started_at = Time.parse(started_at_string)
      runtime = 1.123456
      finished_at = started_at + runtime
      execution_result = instance_double(
        RSpec::Core::Example::ExecutionResult,
        run_time: runtime,
        started_at: started_at,
        finished_at: finished_at,
        exception: nil,
        status: :passed
      )

      example = instance_double(
        RSpec::Core::Example,
        id: "./spec/foo_spec.rb:1",
        execution_result: execution_result,
        metadata: {}
      )

      result = RSpec::Abq::Formatter.abq_result(example)[:test_result]

      expect(result[:runtime]).to eq 1_123_456_000
      expect(result[:started_at]).to eq(started_at_string)
      expect(result[:finished_at]).to eq(finished_at.utc.iso8601(6))
    end
  end
end
