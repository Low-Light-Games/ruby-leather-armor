# frozen_string_literal: true

module DungeonMaster
  # Shared runtime dependencies for entry services that invoke PipelineEngine.
  class EntryRuntime
    attr_reader :adventure, :user, :config, :ai, :log, :sheet, :messenger

    def initialize(adventure:, user:)
      @adventure = adventure
      @user = user
      @config = DmConfig.instance
      @ai = DungeonMaster::AiClient.new(@config)
      @log = DungeonMaster::Logging.new(adventure: adventure, user: user)
      @sheet = DungeonMaster::CharacterBlock.load_sheet(adventure)
      @messenger = DungeonMaster::AdventurePlay::PipelineMessenger.new(
        adventure: adventure,
        log: @log,
        user: user
      )
    end

    def enforce_pipeline_policy!
      raise DungeonMaster::UsageLimitExceeded unless AdventurePolicy.new(user, adventure).pipeline?
    end

    def pipeline_engine
      @pipeline_engine ||= DungeonMaster::PipelineEngine.new(
        adventure: adventure,
        user: user,
        config: config,
        ai: ai,
        log: log,
        sheet: sheet,
        on_progress: method(:broadcast_pipeline_progress),
        on_sheet_update: method(:broadcast_sheet_update),
        on_narrative: messenger.method(:handle_progressive_narrative)
      )
    end

    def ensure_run_pipeline!
      uuid = log.registry_entry_uuid
      return if uuid.blank?

      existing_pipeline_id = AdventureLoop.where(registry_entry_uuid: uuid).where.not(pipeline_id: nil).limit(1).pick(:pipeline_id)
      pipeline = if existing_pipeline_id
                   Pipeline.find_by(id: existing_pipeline_id)
                 else
                   Pipeline.create!(adventure: adventure, player_message_id: log.player_message_id)
                 end
      pipeline_engine.attach_run_pipeline!(pipeline) if pipeline
    end

    def resume_or_start_pipeline!(metadata, message_content)
      original_uuid = metadata&.dig("registry_entry_uuid")
      if original_uuid.present?
        log.resume_registry_entry!(original_uuid, message_content)
      else
        log.start_registry_entry!(message_content)
      end
    end

    private

    def broadcast_pipeline_progress(message)
      AdventureChannel.broadcast_to(adventure, { type: "pipeline_progress", message: message })
    end

    def broadcast_sheet_update
      AdventureChannel.broadcast_to(adventure, { type: "sheet_update" })
    end
  end
end
