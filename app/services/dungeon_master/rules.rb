# frozen_string_literal: true

module DungeonMaster
  # Loads and caches category-specific Pathfinder 1e OGC rule text files
  # from app/services/dungeon_master/rules/.
  module Rules
    CATEGORIES = Prompts::PROMPT_CATEGORIES

    RULES_DIR = File.expand_path("rules", __dir__)

    @cache = {}

    def self.for(category)
      category = category.to_s
      return "" unless CATEGORIES.include?(category)

      # roll_request reuses combat rules by default
      category = "combat" if category == "roll_request"

      @cache[category] ||= begin
        path = File.join(RULES_DIR, "#{category}.txt")
        File.exist?(path) ? File.read(path) : ""
      end
    end

    def self.clear_cache!
      @cache = {}
    end
  end
end
