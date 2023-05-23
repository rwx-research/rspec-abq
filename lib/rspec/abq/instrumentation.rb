module RSpec
  module Abq
    module Instrumentation
      def self.instrument(block_name, &block)
        return block.call unless instrumentation_enabled?

        @current_indentation ||= 0
        @current_indentation += 4
        space_amount = "".ljust(@current_indentation, " ")

        puts "#{space_amount}---- ENTERING #{block_name} ----"
        block.call.tap do
          puts "#{space_amount}---- EXITING #{block_name} ----"
          @current_indentation -= 4
        end
      end

      def self.instrumentation_enabled?
        ENV["ENABLE_RSPEC_ABQ_INSTRUMENTATION"] == "true"
      end
    end
  end
end
