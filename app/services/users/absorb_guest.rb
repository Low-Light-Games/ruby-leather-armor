# frozen_string_literal: true

module Users
  class AbsorbGuest
    REASSIGNED_MODELS = [Adventure, Sheet, AiUsageRecord, Feedback, ModerationEvent].freeze

    def self.call(real_user:, guest:)
      new(real_user: real_user, guest: guest).call
    end

    def initialize(real_user:, guest:)
      @real_user = real_user
      @guest = guest
    end

    def call
      return false unless absorb_targets_valid?

      ActiveRecord::Base.transaction do
        REASSIGNED_MODELS.each do |klass|
          klass.where(user_id: @guest.id).update_all(user_id: @real_user.id)
        end
        @guest.destroy!
      end
      @real_user.reload
      true
    end

    private

    def absorb_targets_valid?
      @guest&.guest? && @real_user && @real_user.id != @guest.id
    end
  end
end
