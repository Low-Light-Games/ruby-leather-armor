# frozen_string_literal: true

class ReplaceGoldWithCurrencyOnSheets < ActiveRecord::Migration[7.1]
  def up
    add_column :sheets, :currency, :jsonb,
               null: false,
               default: { "gold" => 0, "silver" => 0, "copper" => 0, "platinum" => 0 }

    execute <<-SQL.squish
      UPDATE sheets
      SET currency = jsonb_build_object(
        'gold',     COALESCE(gold, 0),
        'silver',   0,
        'copper',   0,
        'platinum',  0
      )
    SQL

    remove_column :sheets, :gold
  end

  def down
    add_column :sheets, :gold, :integer, null: false, default: 0

    execute <<-SQL.squish
      UPDATE sheets
      SET gold = COALESCE((currency->>'gold')::integer, 0)
    SQL

    remove_column :sheets, :currency
  end
end
