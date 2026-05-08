# frozen_string_literal: true

module Combat
  class MoveResolutionPayload
    # @param origin [Combat::Position]
    # @param destination [Hash] x, y
    # @param movement [Hash] distance, mode, battlefield_version
    # @param aoo_outcomes [Array<Combat::NpcAttackOutcome>]
    def initialize(origin:, destination:, movement:, aoo_outcomes:)
      @origin = origin
      @destination = destination
      @movement = movement
      @aoo_outcomes = aoo_outcomes
    end

    def to_h
      {
        kind: 'move',
        from: { x: @origin.x.to_i, y: @origin.y.to_i },
        to: @destination,
        distance_squares: @movement[:distance],
        movement_mode: @movement[:mode],
        battlefield_version: @movement[:battlefield_version],
        attacks_of_opportunity: @aoo_outcomes.map(&:to_h),
        message: build_message
      }
    end

    private

    def build_message
      base = "Moved #{@movement[:distance]} squares (#{@movement[:mode]})."
      return base if @aoo_outcomes.empty?

      hit_count = @aoo_outcomes.count(&:hit)
      suffix = @aoo_outcomes.size == 1 ? '' : 's'
      "#{base} Provoked #{@aoo_outcomes.size} AoO#{suffix} (#{hit_count} hit)."
    end
  end
end
