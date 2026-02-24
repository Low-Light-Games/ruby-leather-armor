class AddRaceAndClassToSheets < ActiveRecord::Migration[7.1]
  def change
    add_column :sheets, :race, :string
    add_column :sheets, :racial_bonus_attribute, :string
    add_column :sheets, :character_class, :string
    add_column :sheets, :subclass, :string
  end
end
