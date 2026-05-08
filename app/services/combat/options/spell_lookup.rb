# frozen_string_literal: true

module Combat
  module Options
    module SpellLookup
      module_function

      # @param raw [String, Symbol] either "spell:<id>" or a bare id
      # @return [String]
      def normalize_id(raw)
        raise ::Combat::ResolverError.new('spell_id is required', code: :missing_spell_id) if raw.to_s.empty?

        raw.to_s.start_with?('spell:') ? raw.to_s.sub(/\Aspell:/, '') : raw.to_s
      end

      # @param raw [String, Symbol] either "spell:<id>" or a bare id
      # @return [SpellDefinition]
      def fetch!(raw)
        spell_id = normalize_id(raw)
        spell = SpellDefinition.find_by(id: spell_id)
        return spell if spell

        raise ::Combat::ResolverError.new("spell not found: #{spell_id.inspect}", code: :spell_not_found)
      end
    end
  end
end
