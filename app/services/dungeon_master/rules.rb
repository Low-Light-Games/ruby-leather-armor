# frozen_string_literal: true

module DungeonMaster
  # Loads and caches category-specific Pathfinder 1e OGC rule text files
  # from app/services/dungeon_master/rules/.
  module Rules
    CATEGORIES = Prompts::PROMPT_CATEGORIES

    RULES_DIR = File.expand_path("rules", __dir__)

    @cache = {}
    @guidance_cache = {}

    def self.for(category)
      category = category.to_s
      return "" unless CATEGORIES.include?(category)

      category = "combat" if category == "roll_request"

      @cache[category] ||= begin
        path = File.join(RULES_DIR, "#{category}.txt")
        File.exist?(path) ? File.read(path) : ""
      end
    end

    def self.guidance_for(category)
      category = category.to_s
      return "" unless CATEGORIES.include?(category)

      category = "combat" if category == "roll_request"

      @guidance_cache[category] ||= begin
        path = File.join(RULES_DIR, "#{category}_guidance.txt")
        File.exist?(path) ? File.read(path) : ""
      end
    end

    def self.clear_cache!
      @cache = {}
      @guidance_cache = {}
    end
  end
end
