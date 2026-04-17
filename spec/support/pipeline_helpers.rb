require "ostruct"
require "webmock"

# ── Evaluator domain list (mirrors ParallelEvaluation::DOMAINS) ─────────────
EVALUATOR_DOMAINS = %w[traversal combat social exploration rest inventory].freeze

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

  # unified_evaluation is retired — kept for reference only; never called.
  "unified_evaluation" => {
    "domains" => {
      "traversal"   => { "affected" => false, "needs_mechanics" => false, "macro_significant" => false },
      "combat"      => { "affected" => false, "needs_mechanics" => false, "macro_significant" => false },
      "social"      => { "affected" => false, "needs_mechanics" => false, "macro_significant" => false, "expand_scene" => false },
      "exploration" => {
        "affected" => true, "needs_mechanics" => false, "macro_significant" => false,
        "domain_interpretation" => "Player opens a door.",
        "player_rolls" => [], "npc_actions" => [], "consequences" => [], "mechanical_summary" => ""
      },
      "rest"      => { "affected" => false, "needs_mechanics" => false, "macro_significant" => false },
      "inventory" => { "affected" => false, "needs_mechanics" => false, "macro_significant" => false }
    },
    "reasoning" => "Simple exploration action."
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

  "meta_context_update" => {
    "scene_summary" => "The adventurer opened a door.",
    "new_creatures" => [],
    "context_wishes" => []
  }.to_json,

  "macro_narrative_update" => {
    "story_summary" => "The adventurer opened a door."
  }.to_json,

  "dm_query" => {
    "answer" => "You can attempt a Perception check (DC 12) to listen at the door."
  }.to_json,

  "mechanic" => {
    "outcome"   => "You succeed on the Perception check and notice a tripwire.",
    "mutations" => {}
  }.to_json,

}.freeze

# ── Shared context — mocked OpenAI (AiClient level) ─────────────────────────
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

# ── Shared context — Node evaluator HTTP stubs (WebMock) ─────────────────────
# Intercepts the three evaluator endpoints used by ParallelEvaluation so specs
# are hermetic and don't require a running evaluator service.
#
# Default behaviour:
#   beacon  — exploration affected, no mechanics
#   mech_eval — no rolls (exploration only, no lock mechanics)
#   roll_qualifier — qualifications: []
#
# Lock-pick detection: if the user_message (player action text) contains "lock",
# the exploration beacon is marked needs_mechanics: true, and mech_eval returns
# a Disable Device DC 15 roll for exploration.
shared_context "with evaluator stubs" do
  before do
    WebMock.enable!
    WebMock.allow_net_connect!(allow_localhost: true)

    evaluator_base = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")

    WebMock.stub_request(:post, "#{evaluator_base}/fan_out")
           .to_return do |request|
      body       = JSON.parse(request.body)
      first_step = body.dig(0, "meta", "step").to_s
      user_msg   = body.dig(0, "user_message").to_s.downcase
      is_lock    = user_msg.include?("lock")

      results = if first_step == "roll_qualifier"
        body.map do |p|
          domain = p.dig("meta", "domain")
          evaluator_entry("roll_qualifier", domain,
                          "parsed_response" => { "qualifications" => [] })
        end
      elsif first_step.start_with?("npc_action")
        body.map do |p|
          st = p.dig("meta", "step").to_s
          evaluator_entry(st, nil,
                          "parsed_response" => {
                            "action" => "attack",
                            "target" => "Player",
                            "attack_modifier" => 5,
                            "damage_dice" => "1d4",
                            "reasoning" => "stub npc turn"
                          })
        end
      elsif first_step == "beacon"
        body.map do |p|
          domain     = p.dig("meta", "domain")
          needs_mech = is_lock && domain == "exploration"
          evaluator_entry("beacon", domain,
                          "parsed_response" => {
                            "affected"          => domain == "exploration",
                            "needs_mechanics"   => needs_mech,
                            "macro_significant" => false,
                            "expand_scene"      => false,
                            "transition"        => nil,
                            "destination"       => nil,
                            "combatants"        => [],
                            "reasoning"         => domain == "exploration" ? "Exploration action" : "Not affected"
                          })
        end
      else
        # sanity_gate, context_update, narrative_phase — each item by meta.step
        body.map do |p|
          st = p.dig("meta", "step").to_s
          case st
          when "sanity_checker_world"
            evaluator_entry("sanity_checker_world", nil,
                            "parsed_response" => JSON.parse(AI_STEP_RESPONSES["sanity_checker_world"]))
          when "sanity_checker"
            evaluator_entry("sanity_checker", nil,
                            "parsed_response" => { "allowed" => true, "reason" => nil })
          when "micro_context_update"
            evaluator_entry("micro_context_update", nil,
                            "parsed_response" => JSON.parse(AI_STEP_RESPONSES["micro_context_update"]))
          when "meta_context_update"
            evaluator_entry("meta_context_update", nil,
                            "parsed_response" => JSON.parse(AI_STEP_RESPONSES["meta_context_update"]))
          when /\A[a-z]+_context_update\z/
            domain = st.sub(/_context_update\z/, "")
            evaluator_entry(st, domain,
                            "parsed_response" => {
                              "unchanged" => true,
                              "context" => {}
                            })
          when "macro_narrative_update"
            evaluator_entry("macro_narrative_update", nil,
                            "parsed_response" => JSON.parse(AI_STEP_RESPONSES["macro_narrative_update"]))
          when "narrate"
            evaluator_entry("narrate", nil,
                            "parsed_response" => JSON.parse(AI_STEP_RESPONSES["narrate"]))
          else
            domain     = p.dig("meta", "domain")
            needs_mech = is_lock && domain == "exploration"
            evaluator_entry("beacon", domain,
                            "parsed_response" => {
                              "affected"          => domain == "exploration",
                              "needs_mechanics"   => needs_mech,
                              "macro_significant" => false,
                              "expand_scene"      => false,
                              "transition"        => nil,
                              "destination"       => nil,
                              "combatants"        => [],
                              "reasoning"         => domain == "exploration" ? "Exploration action" : "Not affected"
                            })
          end
        end
      end

      { status: 200, body: results.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    WebMock.stub_request(:post, "#{evaluator_base}/sequential")
           .to_return do |request|
      body     = JSON.parse(request.body)
      user_msg = body.dig(0, "user_message").to_s.downcase
      is_lock  = user_msg.include?("lock")

      results = body.map do |p|
        domain = p.dig("meta", "domain")
        # Combat domain: non-empty player_rolls must match CombatMechanicResolution (see stub_openai sequential).
        if is_lock && domain == "exploration"
          evaluator_entry("mechanical_evaluation", domain,
                          "parsed_response" => {
                            "player_rolls"       => [{ "type" => "skill_check", "skill" => "Disable Device",
                                                       "dc" => 15, "description" => "Pick the lock" }],
                            "npc_actions"        => [],
                            "consequences"       => [],
                            "mechanical_summary" => "Player must beat DC 15 Disable Device"
                          })
        else
          evaluator_entry("mechanical_evaluation", domain,
                          "parsed_response" => {
                            "player_rolls"       => [],
                            "npc_actions"        => [],
                            "consequences"       => [],
                            "mechanical_summary" => "No mechanical interaction"
                          })
        end
      end

      { status: 200, body: results.to_json,
        headers: { "Content-Type" => "application/json" } }
    end
  end

  after do
    WebMock.reset!
    WebMock.disable!
  end

  private

  # Builds a single evaluator result envelope matching the Node service shape.
  def evaluator_entry(step, domain, overrides = {})
    {
      "raw_response"    => "stub",
      "parse_status"    => "success",
      "parsed_response" => {},
      "meta"            => { "step" => step, "domain" => domain },
      "usage"           => { "input_tokens" => 80, "output_tokens" => 30,
                             "reasoning_tokens" => 0, "total_tokens" => 110 },
      "model_used"      => "gpt-4o-mini",
      "duration_ms"     => 50,
      "request_body"    => {}
    }.merge(overrides)
  end
end

# ── Pipeline builder helpers ─────────────────────────────────────────────────
module PipelineHelpers
  # Build a real Pipeline instance with a real Adventure / DmConfig,
  # but a stubbed AiClient and a nulled-out logger.
  def build_pipeline(adventure, config: nil, on_narrative: nil)
    config ||= DmConfig.instance
    ai  = DungeonMaster::AiClient.new(config)
    log = build_nulled_logger(adventure)
    sheet = DungeonMaster::CharacterBlock.load_sheet(adventure)

    DungeonMaster::PipelineEngine.new(
      adventure:    adventure,
      config:       config,
      ai:           ai,
      log:          log,
      sheet:        sheet,
      on_narrative: on_narrative
    )
  end

  private

  # A logger double that accepts every call and returns safe defaults.
  # We use a real Logging object but stub the methods that make DB writes or
  # external calls — the test DB can handle AdventureLoop creates, but we
  # skip PlayLog / PipelineRegistryEntry to keep specs lean.
  def build_nulled_logger(adventure)
    log = DungeonMaster::Logging.new(adventure: adventure, user: adventure.user)
    # Pre-set registry_entry_uuid so AdventureLoop.create! passes its presence validation.
    # DungeonMasterService normally calls start_registry_entry! before the pipeline runs,
    # but in unit tests we skip that service layer entirely.
    log.registry_entry_uuid = SecureRandom.uuid
    allow(log).to receive(:start_registry_entry!) { }
    allow(log).to receive(:resume_registry_entry!) { }
    allow(log).to receive(:finish_pipeline_segment!) { }
    allow(log).to receive(:pause_registry_entry!) { }
    allow(log).to receive(:complete_registry_entry!) { }
    allow(log).to receive(:error_registry_entry!) { }
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
