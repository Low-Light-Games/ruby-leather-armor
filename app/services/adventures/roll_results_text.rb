# frozen_string_literal: true

module Adventures
  module RollResultsText
    module_function

    def format(rolls)
      return rolls if rolls.is_a?(String)

      Array(rolls).map do |r|
        r = r.deep_symbolize_keys if r.respond_to?(:deep_symbolize_keys)
        case r[:resolution_method].to_s
        when "take_20"
          "Take 20 (result #{r[:roll_value]}) for: #{r[:roll_description]}"
        when "take_10"
          "Take 10 (result #{r[:roll_value]}) for: #{r[:roll_description]}"
        else
          "Rolled #{r[:roll_value]} for: #{r[:roll_description]}"
        end
      end.join("\n")
    end
  end
end
