# frozen_string_literal: true

module Adventures
  module ValueObjects
    class CombatState
      attr_reader :round, :current_turn, :participants, :turn_order,
                  :action_economy, :battlefield_ref, :last_battlefield_ref,
                  :terrain_notes

      def self.from_adventure(adventure)
        from_raw(adventure&.combat_context)
      end

      def self.from_raw(raw)
        ctx = raw.is_a?(Hash) ? raw : {}
        new(
          active:               ctx["active"] == true,
          round:                ctx["round"],
          current_turn:         ctx["current_turn"],
          participants:         build_participants(ctx["participants"]),
          turn_order:           Array(ctx["turn_order"]).map(&:to_s),
          action_economy:       (ctx["action_economy"].is_a?(Hash) ? ctx["action_economy"] : {}),
          battlefield_ref:      ctx["battlefield_ref"],
          last_battlefield_ref: ctx["last_battlefield_ref"],
          terrain_notes:        ctx["terrain_notes"],
          raw:                  ctx,
        )
      end

      def self.build_participants(raw)
        Array(raw).filter_map { |entry| Participant.from_raw(entry) }
      end
      private_class_method :build_participants

      def initialize(active:, round:, current_turn:, participants:, turn_order:,
                     action_economy:, battlefield_ref:, last_battlefield_ref:,
                     terrain_notes:, raw:)
        @active               = active
        @round                = round
        @current_turn         = current_turn
        @participants         = participants
        @turn_order           = turn_order
        @action_economy       = action_economy
        @battlefield_ref      = battlefield_ref
        @last_battlefield_ref = last_battlefield_ref
        @terrain_notes        = terrain_notes
        @raw                  = raw
      end

      def active? = @active
      def has_participants? = @participants.any?
      def participant_names = @participants.map(&:name)

      def to_h = @raw

      class Participant
        attr_reader :name, :type, :hp, :max_hp

        def self.from_raw(raw)
          return nil unless raw.is_a?(Hash)

          new(
            name:   (raw["name"] || raw[:name]).to_s,
            type:   raw["type"] || raw[:type],
            hp:     raw["hp"] || raw[:hp],
            max_hp: raw["max_hp"] || raw[:max_hp],
          )
        end

        def initialize(name:, type: nil, hp: nil, max_hp: nil)
          @name   = name
          @type   = type
          @hp     = hp
          @max_hp = max_hp
        end

        def player?  = @type.to_s == "player"
        def hostile? = !player?
        def alive?   = @hp.is_a?(Numeric) && @hp.positive?
      end
    end
  end
end
