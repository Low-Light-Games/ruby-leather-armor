# frozen_string_literal: true

class LinkNpcsToCreatureDefinitions < ActiveRecord::Migration[7.1]
  def change
    # adventure_npcs gets a runtime CreatureSheet pointer (bigint FK).
    add_reference :adventure_npcs, :creature_sheet,
                  foreign_key: true, null: true, index: true

    # story_npcs gets an authoring-time BestiaryEntry pointer.
    # bestiary_entries.id is a :string column, so the FK column type must match.
    add_column    :story_npcs, :bestiary_entry_id, :string
    add_index     :story_npcs, :bestiary_entry_id
    add_foreign_key :story_npcs, :bestiary_entries, column: :bestiary_entry_id
  end
end
