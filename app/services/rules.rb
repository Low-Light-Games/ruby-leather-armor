# frozen_string_literal: true

module Rules
  DOMAINS = %w[combat traversal social exploration rest inventory magic].freeze
  ENTRIES_DIR = File.expand_path("rules/entries", __dir__)
  GUIDANCE_DIR = File.expand_path("rules", __dir__)

  @entries = nil
  @guidance_cache = {}

  class << self
    def all_entries
      @entries ||= load_all_entries
    end

    def guidance_for(domain)
      domain = domain.to_s
      return "" unless DOMAINS.include?(domain)

      @guidance_cache[domain] ||= begin
        path = File.join(GUIDANCE_DIR, "#{domain}_guidance.txt")
        File.exist?(path) ? File.read(path).strip : ""
      end
    end

    def clear_cache!
      @entries = nil
      @guidance_cache = {}
    end

    private

    def load_all_entries
      entries = {}
      DOMAINS.each do |domain|
        path = File.join(ENTRIES_DIR, "#{domain}.yml")
        next unless File.exist?(path)

        yaml = YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
        yaml.each do |slug, data|
          entries[slug] = {
            name: data["name"],
            domain: domain,
            text: data["text"] || "",
            related: Array(data["related"]).map(&:to_s)
          }
        end
      end
      entries.freeze
    end
  end
end
