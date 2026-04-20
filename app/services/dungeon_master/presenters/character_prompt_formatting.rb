# frozen_string_literal: true

module DungeonMaster
  module Presenters
    # Shared string helpers for prompt-facing character/creature presenters.
    module CharacterPromptFormatting
      def format_mod(val)
        return "+0" unless val

        val >= 0 ? "+#{val}" : val.to_s
      end

      def format_currency(currency)
        return "none" unless currency.is_a?(Hash)

        parts = []
        parts << "#{currency['platinum']} pp" if currency["platinum"].to_i > 0
        parts << "#{currency['gold']} gp"     if currency["gold"].to_i > 0
        parts << "#{currency['silver']} sp"   if currency["silver"].to_i > 0
        parts << "#{currency['copper']} cp"   if currency["copper"].to_i > 0
        parts.empty? ? "none" : parts.join(", ")
      end

      def format_carry(ds)
        caps = ds["carry_capacity"]
        return "unknown" unless caps.is_a?(Hash)

        "#{ds['total_weight'] || '?'}/#{caps['heavy'] || '?'} lbs"
      end
    end
  end
end
