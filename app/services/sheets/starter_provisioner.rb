# frozen_string_literal: true

module Sheets
  class StarterProvisioner
    STARTER_KEYS = Onboarding::PrebuiltCharacters::ALL.keys.freeze

    def self.ensure_for(user:, starter_key:)
      new(user: user).ensure_for!(starter_key)
    end

    def self.ensure_all_for(user:)
      new(user: user).ensure_all!
    end

    def initialize(user:)
      @user = user
    end

    def ensure_all!
      STARTER_KEYS.map { |starter_key| ensure_for!(starter_key) }
    end

    def ensure_for!(starter_key)
      starter_key = starter_key.to_s.downcase
      blueprint = Onboarding::SheetBlueprint.new(Onboarding::PrebuiltCharacters.find(starter_key))

      Sheet.transaction do
        sheet = @user.sheets.starter.find_or_initialize_by(starter_key: starter_key)
        sheet.assign_attributes(
          blueprint.sheet_attributes.merge(
            source_kind: :starter,
            starter_key: starter_key,
          ),
        )
        sheet.save! if sheet.new_record? || sheet.changed?

        replace_feats!(sheet, resolve_feat_ids(blueprint.feat_names))
        replace_items!(sheet, resolve_item_entries(blueprint.item_names))
        replace_spells!(sheet)
        sheet.recompute_derived_stats!
        sheet
      end
    end

    private

    def resolve_feat_ids(feat_names)
      feat_names.filter_map do |name|
        FeatDefinition.find_by("LOWER(name) = LOWER(?)", name)&.id
      end
    end

    def resolve_item_entries(item_names)
      item_names.filter_map do |name|
        defn = ItemDefinition.find_by("LOWER(name) = LOWER(?)", name)
        next unless defn

        { item_id: defn.id, quantity: 1, equipped: false }
      end
    end

    def replace_feats!(sheet, feat_ids)
      sheet.sheet_feats.delete_all

      feat_ids.each do |feat_id|
        next unless FeatDefinition.exists?(feat_id)

        sheet.sheet_feats.create!(feat_id: feat_id)
      end
    end

    def replace_items!(sheet, item_entries)
      sheet.sheet_items.delete_all

      item_entries.each do |entry|
        sheet.sheet_items.create!(
          item_definition_id: entry[:item_id],
          quantity: entry[:quantity],
          equipped: entry[:equipped],
        )
      end
    end

    def replace_spells!(sheet)
      sheet.sheet_spells.delete_all
    end
  end
end
