# frozen_string_literal: true

class OnboardingController < ApplicationController
  def complete
    character_type = params[:character_type].to_s.downcase
    unless %w[rogue fighter].include?(character_type)
      return render json: { error: "Invalid character type" }, status: :unprocessable_entity
    end

    story = Story.kept.order("RANDOM()").first
    unless story
      return render json: { error: "No adventures are available yet. Build your own character to get started." }, status: :unprocessable_entity
    end

    character_data = Onboarding::PrebuiltCharacters.find(character_type)

    ActiveRecord::Base.transaction do
      sheet = build_sheet!(character_data)
      adventure = build_adventure!(story, sheet)
      current_user.update!(onboarding_state: "in_progress")
      render json: { adventure_id: adventure.id }, status: :created
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def build_sheet!(data)
    blueprint = Onboarding::SheetBlueprint.new(data)
    sheet = current_user.sheets.create!(blueprint.sheet_attributes)

    sync_feats!(sheet.sheet_feats, resolve_feat_ids(blueprint.feat_names))
    sync_items!(sheet.sheet_items, resolve_item_entries(blueprint.item_names))
    sheet.recompute_derived_stats!
    sheet
  end

  def build_adventure!(story, sheet)
    Adventures::Bootstrap.new(
      story:                   story,
      sheet:                   sheet,
      user:                    current_user,
      directed_dm:             true,
      skip_world_sanity_check: false
    ).call
  end

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

  def sync_feats!(feat_relation, feat_ids)
    feat_ids.each do |feat_id|
      next unless FeatDefinition.exists?(feat_id)

      feat_relation.create!(feat_id: feat_id)
    end
  end

  def sync_items!(item_relation, item_entries)
    item_entries.each do |entry|
      item_relation.create!(
        item_definition_id: entry[:item_id],
        quantity:           entry[:quantity],
        equipped:           entry[:equipped],
      )
    end
  end

end
