# frozen_string_literal: true

module Admin
  class BestiaryEntriesController < BaseController

    def index
      @entries = BestiaryEntry.order(:name)
      @entries = @entries.where("LOWER(name) LIKE ?", "%#{params[:q].downcase}%") if params[:q].present?
      @total = BestiaryEntry.count
      @ai_candidates = CreatureSheet.where(origin: "ai").select(:name).distinct.pluck(:name)
    end

    def import_candidates
      sheets = CreatureSheet.where(origin: "ai").order(:name)
      @candidates = sheets.group_by(&:name).map do |name, group|
        representative = group.max_by(&:updated_at)
        existing = BestiaryEntry.where("LOWER(name) = ?", name.downcase.strip.singularize).exists?
        { sheet: representative, count: group.size, already_in_bestiary: existing }
      end
    end

    def import
      sheet = CreatureSheet.find(params[:creature_sheet_id])

      name = params[:bestiary_name].presence || sheet.name
      entry_id = name.downcase.strip.gsub(/\s+/, "_")

      if BestiaryEntry.exists?(id: entry_id)
        redirect_to import_candidates_admin_bestiary_entries_path,
                    alert: "A bestiary entry with id '#{entry_id}' already exists."
        return
      end

      hp_formula = reverse_hp_formula(sheet)

      BestiaryEntry.create!(
        id: entry_id,
        name: name,
        source: "ai_import",
        cr: sheet.level,
        creature_type: sheet.creature_type,
        strength: sheet.strength,
        dexterity: sheet.dexterity,
        constitution: sheet.constitution,
        intelligence: sheet.intelligence,
        wisdom: sheet.wisdom,
        charisma: sheet.charisma,
        hp_formula: hp_formula,
        ac: sheet.derived_stats&.dig("ac"),
        base_attack: sheet.derived_stats&.dig("bab"),
        speed: sheet.derived_stats&.dig("speed"),
        description: sheet.description
      )

      redirect_to admin_bestiary_entries_path,
                  notice: "'#{name}' imported into the bestiary from AI-generated creature sheet."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to import_candidates_admin_bestiary_entries_path,
                  alert: "Import failed: #{e.message}"
    end

    private

    def require_admin
      redirect_to root_path, alert: "Unauthorized" unless current_user&.admin?
    end

    def reverse_hp_formula(sheet)
      return "1d10+2" unless sheet.max_hp && sheet.constitution
      con_mod = ((sheet.constitution - 10).to_f / 2).floor
      level = [sheet.level, 1].max
      flat_bonus = con_mod * level
      remaining = [sheet.max_hp - flat_bonus, level].max
      die_avg = (remaining.to_f / level).round
      die_size = [die_avg * 2, 4].max
      sign = flat_bonus >= 0 ? "+" : ""
      "#{level}d#{die_size}#{sign}#{flat_bonus}"
    end
  end
end
