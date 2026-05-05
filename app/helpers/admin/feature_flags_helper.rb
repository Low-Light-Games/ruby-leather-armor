# frozen_string_literal: true

module Admin
  module FeatureFlagsHelper
    def bucket_summary(flag)
      case flag.mode
      when "off"      then "—"
      when "on"       then "(everyone)"
      when "bucketed" then bucketed_summary(flag)
      end
    end

    def mode_hint(mode)
      case mode
      when "off"      then "Disabled for everyone."
      when "on"       then "Enabled for everyone."
      when "bucketed" then "Enabled for a subset of users — choose a strategy below."
      end
    end

    def strategy_hint(strategy)
      case strategy
      when "granular" then "Specific user IDs are ON; everyone else is OFF."
      when "modulo"   then "user.id % divisor matches a remainder → ON. Useful for percentage rollouts."
      end
    end

    private

    def bucketed_summary(flag)
      case flag.bucketing_strategy
      when "granular"
        count = flag.granular_user_ids.size
        "granular: #{count} user#{'s' unless count == 1}"
      when "modulo"
        "modulo #{flag.modulo_divisor}, on=[#{flag.modulo_on_remainders.join(',')}] (#{modulo_percentage(flag)}%)"
      else
        "(no strategy set)"
      end
    end

    def modulo_percentage(flag)
      return 0 if flag.modulo_divisor.to_i.zero?

      ((flag.modulo_on_remainders.size.to_f / flag.modulo_divisor) * 100).round
    end
  end
end
