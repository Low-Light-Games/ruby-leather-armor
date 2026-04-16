# frozen_string_literal: true

class BackfillCreatureSheetTouchAndFlatFootedAc < ActiveRecord::Migration[7.1]
  def up
    say_with_time "recomputing creature_sheets missing touch_ac / flat_footed_ac" do
      CreatureSheet.find_each do |sheet|
        ds = sheet.derived_stats
        next if ds.is_a?(Hash) && ds["touch_ac"].present? && ds["flat_footed_ac"].present?

        sheet.recompute_derived_stats!
      rescue StandardError => e
        say "skip creature_sheets.id=#{sheet.id}: #{e.class}: #{e.message}", true
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
