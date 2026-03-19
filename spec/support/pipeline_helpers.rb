require "ostruct"

# ── Minimal AI response map ─────────────────────────────────────────────────
# Each key matches the step_name: kwarg passed to AiClient#chat.
# Values are realistic minimal JSON strings the pipeline can parse.
AI_STEP_RESPONSES = {
  "intake" => {
    "sanitized_input" => "I open the door carefully.",
    "danger_score"    => 0,
    "reason"          => "Benign exploration action.",
    "is_dm_query"     => false
  }.to_json,

  "sequencer" => {
    "actions" => ["open the door carefully"]
  }.to_json,

  "player_interpreter" => {
    "intention" => "The adventurer opens the door carefully."
  }.to_json,

  # Per-domain beacon response. "affected": true is required for converge_beacons
  # to register any affected contexts; "needs_mechanics": false routes through
  # the non-mechanical (momentum) path for the default happy-path specs.
  "beacon" => {
    "affected"          => true,
    "needs_mechanics"   => false,
    "expand_scene"      => false,
    "destination"       => nil,
    "rules_needed"      => [],
    "transition"        => nil,
    "macro_significant" => false,
    "domain_interpretation" => "Player opens a door."
  }.to_json,

  "sanity_checker" => {
    "consistent"  => true,
    "reason"      => nil,
    "dm_message"  => nil
  }.to_json,

  "sanity_checker_world" => {
    "consistent"  => true,
    "reason"      => nil,
    "dm_message"  => nil
  }.to_json,

  "time_keeper" => {
    "hours_elapsed" => 0.1,
    "encounter"     => false,
    "journey_data"  => nil
  }.to_json,

  "momentum" => {
    "outcome"           => "The door swings open to reveal a dark corridor.",
    "mutations"         => {},
    "affected_contexts" => ["exploration"]
  }.to_json,

  "chronicler" => {
    "dm_brief"          => "Player opened a door.",
    "clues_revealed"    => [],
    "npc_reactions"     => [],
    "milestones_reached" => []
  }.to_json,

  "narrate" => {
    "narrative" => "The heavy oak door groans as it swings open. A cold draft carries the smell of old stone."
  }.to_json,

  "micro_context_update" => {
    "context_updates" => {}
  }.to_json,

  "macro_narrative_update" => {
    "story_summary" => "The adventurer opened a door."
  }.to_json,

  "dm_query" => {
    "answer" => "You can attempt a Perception check (DC 12) to listen at the door."
  }.to_json,

  # Mechanical path responses (for roll-pause specs)
  "mechanical_evaluation" => {
    "player_rolls"        => [{ "skill" => "Perception", "type" => "skill_check", "dc" => 12, "domain" => "exploration" }],
    "npc_actions"         => [],
    "consequences"        => [],
    "mechanical_summary"  => "Perception check required."
  }.to_json,

  "roll_qualifier" => {
    "player_rolls" => [{ "skill" => "Perception", "type" => "skill_check", "dc" => 12, "domain" => "exploration",
                         "take_10_eligible" => false, "take_10_value" => nil }]
  }.to_json,

  "mechanic" => {
    "outcome"   => "You succeed on the Perception check and notice a tripwire.",
    "mutations" => {}
  }.to_json,

  "edge_pipeline" => {
    "narrative"        => "The door creaks open. Inside, darkness waits.",
    "adventure_complete" => false
  }.to_json
}.freeze

# ── Shared context ───────────────────────────────────────────────────────────
shared_context "with mocked ai" do
  let(:ai_responses) { AI_STEP_RESPONSES }

  before do
    allow_any_instance_of(DungeonMaster::AiClient).to receive(:chat) do |instance, **kwargs|
      step = kwargs[:step_name].to_s
      response = ai_responses.fetch(step, '{"result":"ok"}')
      # Set the tracking attrs that timed_ai_call reads back
      instance.instance_variable_set(:@last_parse_status, "success")
      instance.instance_variable_set(:@last_model_used, "gpt-4o-mini-test")
      instance.instance_variable_set(:@last_usage, { "prompt_tokens" => 10, "completion_tokens" => 20 })
      response
    end
  end
end

# ── Pipeline builder helpers ─────────────────────────────────────────────────
module PipelineHelpers
  # Build a real Pipeline instance with a real Adventure / DmConfig,
  # but a stubbed AiClient and a nulled-out logger.
  def build_pipeline(adventure, config: nil)
    config ||= DmConfig.instance
    ai  = DungeonMaster::AiClient.new(config)
    log = build_nulled_logger(adventure)
    sheet = DungeonMaster::CharacterBlock.load_sheet(adventure)

    DungeonMaster::Pipeline.new(
      adventure: adventure,
      config:    config,
      ai:        ai,
      log:       log,
      sheet:     sheet
    )
  end

  def build_edge_pipeline(adventure, config: nil)
    config ||= DmConfig.instance
    ai  = DungeonMaster::AiClient.new(config)
    log = build_nulled_logger(adventure)
    sheet = DungeonMaster::CharacterBlock.load_sheet(adventure)

    DungeonMaster::EdgePipeline.new(
      adventure: adventure,
      config:    config,
      ai:        ai,
      log:       log,
      sheet:     sheet
    )
  end

  private

  # A logger double that accepts every call and returns safe defaults.
  # We use a real Logging object but stub the methods that make DB writes or
  # external calls — the test DB can handle AdventureLoop creates, but we
  # skip PlayLog / PipelineRun to keep specs lean.
  def build_nulled_logger(adventure)
    log = DungeonMaster::Logging.new(adventure: adventure, user: adventure.user)
    # Pre-set pipeline_run_id so AdventureLoop.create! passes its presence validation.
    # DungeonMasterService normally calls start_pipeline_run! before the pipeline runs,
    # but in unit tests we skip that service layer entirely.
    log.pipeline_run_id = SecureRandom.uuid
    allow(log).to receive(:start_pipeline_run!) { }
    allow(log).to receive(:resume_pipeline_run!) { }
    allow(log).to receive(:finish_pipeline_segment!) { }
    allow(log).to receive(:pause_pipeline_run!) { }
    allow(log).to receive(:complete_pipeline_run!) { }
    allow(log).to receive(:error_pipeline_run!) { }
    allow(log).to receive(:ai_log!) { }
    allow(log).to receive(:ai_log_error!) { }
    allow(log).to receive(:play_log!) { }
    allow(log).to receive(:log!) { }
    allow(log).to receive(:truncate) { |s| s.to_s.truncate(100) }
    log
  end
end

RSpec.configure do |config|
  config.include PipelineHelpers, type: :service
end
