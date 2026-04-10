# frozen_string_literal: true

module SheetJsonSerialization
  extend ActiveSupport::Concern

  private

  # Delegates to SheetPresenter to build a JSON-ready hash for any sheet-like
  # record, merging feat/spell/item pivot data into the details hash for
  # backward compatibility with the frontend.
  def serialize_sheet_json(sheet, feat_rel:, spell_rel:, item_rel:)
    SheetPresenter.new(sheet, feat_rel: feat_rel, spell_rel: spell_rel, item_rel: item_rel).as_json
  end
end
