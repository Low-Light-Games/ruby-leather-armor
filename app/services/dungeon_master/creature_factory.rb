# frozen_string_literal: true

module DungeonMaster
  # TODO: Improve readability — class may be obsolete; resolution lives in Encounters::Warmaster and the only documented caller (Mutations#handle_new_creatures) is unreachable.
  class CreatureFactory
    CREATURE_TEMPLATE = {
      1  => { str: 13, dex: 13, con: 12, int: 6,  wis: 10, cha: 8,  ac: 13, bab: 1,  hp: "1d10+2",   speed: 30 },
      2  => { str: 14, dex: 13, con: 13, int: 6,  wis: 10, cha: 8,  ac: 14, bab: 2,  hp: "2d10+4",   speed: 30 },
      3  => { str: 15, dex: 14, con: 13, int: 7,  wis: 11, cha: 8,  ac: 15, bab: 3,  hp: "3d10+6",   speed: 30 },
      5  => { str: 17, dex: 14, con: 14, int: 8,  wis: 11, cha: 9,  ac: 17, bab: 5,  hp: "5d10+10",  speed: 30 },
      8  => { str: 19, dex: 15, con: 16, int: 8,  wis: 12, cha: 10, ac: 20, bab: 8,  hp: "8d10+24",  speed: 30 },
      10 => { str: 21, dex: 16, con: 17, int: 9,  wis: 12, cha: 10, ac: 22, bab: 10, hp: "10d10+30", speed: 30 },
    }.freeze

    # @param adventure [Adventure]
    # @param sheet     [AdventureSheet, nil]  player sheet (used for party_level fallback)
    # @param log       [Ai::Logging]
    # @param ai        [Ai::Client]
    # @param config    [DmConfig]
    def initialize(adventure, sheet:, log:, ai:, config:)
      @adventure = adventure
      @sheet     = sheet
      @log       = log
      @ai        = ai
      @config    = config
    end

    # Creates a CreatureSheet for +name+ if one does not already exist.
    # Returns the CreatureSheet on success, nil on failure or skip.
    def create_for_name(name)
      return nil if @adventure.creature_sheets.exists?(name: name)

      bestiary = fuzzy_bestiary_match(name)
      if bestiary
        create_from_bestiary(bestiary, name)
      else
        sheet = resolve_dynamic(name, party_level: @sheet&.level || 1)
        if sheet.nil?
          @log.log!(:warn, "No bestiary match for '#{name}' — creature creation disabled or failed")
        end
        sheet
      end
    end

    private

    def fuzzy_bestiary_match(name)
      return nil unless defined?(BestiaryEntry)

      normalized = name.downcase.strip.singularize
      BestiaryEntry.find_by("LOWER(name) = ?", normalized) ||
        BestiaryEntry.where("LOWER(name) LIKE ?", "%#{normalized}%").first ||
        BestiaryEntry.find_by(id: normalized.gsub(/\s+/, "_"))
    end

    def resolve_dynamic(name, party_level:)
      mode = @config.get("creature_creation_fallback") || "ai"
      case mode
      when "ai"       then create_from_ai(name, party_level)
      when "template" then create_from_template(name, party_level)
      end
    rescue => e
      ApplicationErrorReporter.notify(e, context: { source: "creature_factory_resolve_dynamic", creature_name: name })
      @log.log!(:error, "dynamic_creature failed for '#{name}': #{e.message}")
      nil
    end

    def create_from_bestiary(entry, display_name)
      hp   = roll_hp(entry.hp_formula)
      attrs = entry.to_creature_sheet_attrs(display_name: display_name)
      sheet = @adventure.creature_sheets.create!(attrs.merge(hp: hp, max_hp: hp, origin: "bestiary"))
      sheet.recompute_derived_stats!
      sheet
    end

    def create_from_template(name, party_level)
      tier  = CREATURE_TEMPLATE.keys.select { |k| k <= party_level }.max || 1
      stats = CREATURE_TEMPLATE[tier]
      hp    = roll_hp(stats[:hp])

      sheet = @adventure.creature_sheets.create!(
        name: name,
        creature_type: "monster",
        origin: "template",
        strength: stats[:str], dexterity: stats[:dex], constitution: stats[:con],
        intelligence: stats[:int], wisdom: stats[:wis], charisma: stats[:cha],
        level: [party_level, 1].max,
        hp: hp, max_hp: hp,
        derived_stats: { "ac" => stats[:ac], "bab" => stats[:bab], "speed" => stats[:speed] }
      )
      sheet.recompute_derived_stats!
      sheet
    end

    def create_from_ai(name, party_level)
      t0             = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      prompt_summary = "CreatureGeneration: #{name} (party level #{party_level})"

      system_prompt, user_msg = Ai::PromptRenderer.render_with_user_message("creature_generation",
        creature_name: name, party_level: party_level)

      request_body = { system_prompt: system_prompt, user_message: user_msg }
      raw = @ai.chat(
        system_prompt: system_prompt,
        user_message: user_msg,
        step_name:    "creature_generation",
        model:        @config.model_for("creature_generation")
      )

      parsed      = @ai.parse_json(raw)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round

      @log.ai_log!("creature_generation", prompt_summary, raw, parsed,
        parse_status: @ai.last_parse_status, request_body: request_body,
        model_used:   @ai.last_model_used, duration_ms: duration_ms,
        usage:        @ai.last_usage)

      hp = roll_hp(parsed["hp_formula"])
      sheet = @adventure.creature_sheets.create!(
        name: name,
        creature_type: parsed["creature_type"] || "monster",
        origin: "ai",
        strength:     parsed["strength"].to_i.clamp(1, 40),
        dexterity:    parsed["dexterity"].to_i.clamp(1, 40),
        constitution: parsed["constitution"].to_i.clamp(1, 40),
        intelligence: parsed["intelligence"].to_i.clamp(1, 40),
        wisdom:       parsed["wisdom"].to_i.clamp(1, 40),
        charisma:     parsed["charisma"].to_i.clamp(1, 40),
        level:        [parsed["cr"].to_i, 1].max,
        hp: hp, max_hp: hp,
        derived_stats: {
          "ac"  => parsed["ac"].to_i,
          "bab" => parsed["base_attack"].to_i,
          "speed" => parsed["speed"].to_i
        }
      )
      sheet.recompute_derived_stats!
      sheet
    end

    def roll_hp(formula)
      return 10 unless formula.present?

      if formula =~ /(\d+)d(\d+)([+-]\d+)?/
        count, die, mod = $1.to_i, $2.to_i, ($3 || 0).to_i
        count.times.sum { rand(1..die) } + mod
      else
        formula.to_i.nonzero? || 10
      end
    end
  end
end
