# frozen_string_literal: true

class GameMasterLoremasterJob < ApplicationJob
  queue_as :dm_pipeline
  discard_on ActiveRecord::RecordNotFound

  def perform(adventure_id, narrative, registry_entry_uuid: nil, adventure_loop_id: nil, user_id: nil)
    adventure = Adventure.find(adventure_id)
    user = resolve_user(adventure, user_id)
    loop = resolve_loop(adventure, adventure_loop_id)
    config = DmConfig.instance
    ai = Ai::Client.new(config)
    log = Ai::Logging.new(adventure: adventure, user: user)
    log.registry_entry_uuid = registry_entry_uuid.presence
    log.adventure_loop = loop

    PlayerTurn::GameMasterLoremasterAsync.call(
      adventure: adventure,
      config: config,
      ai: ai,
      log: log,
      narrative: narrative,
      loop: loop
    )
  rescue StandardError => e
    ApplicationErrorReporter.notify(e, context: {
      source: "game_master_loremaster_job",
      adventure_id: adventure_id,
      adventure_loop_id: adventure_loop_id,
      registry_entry_uuid: registry_entry_uuid
    })
    raise
  end

  private

  def resolve_user(adventure, user_id)
    return User.find(user_id) if user_id.present?

    return adventure.user if adventure.respond_to?(:user) && adventure.user.present?

    raise ActiveRecord::RecordNotFound, "Missing user for GameMasterLoremasterJob adventure_id=#{adventure.id}"
  end

  def resolve_loop(adventure, adventure_loop_id)
    return nil if adventure_loop_id.blank?

    adventure.adventure_loops.find_by(id: adventure_loop_id)
  end
end
