# When STUB_OPENAI=true is set (e.g. during Playwright E2E runs), intercept
# all outbound AI calls at the HTTP layer and return canned responses so tests
# never depend on a real API key, network access, or a running evaluator.
if ENV["STUB_OPENAI"].present?
  require "webmock"
  WebMock.enable!
  WebMock.allow_net_connect!(allow_localhost: true)

  # ── OpenAI response map ────────────────────────────────────────────────────
  # Matched against the first line of the system prompt.
  # The sequencer always returns 3 actions for the E2E compound-action scenario.
  OPENAI_STEP_RESPONSES = {
    "compound action detector" =>
      { "actions" => ["scout the corridor", "pick the lock", "push the door open"] }.to_json,

    "intake filter" =>
      { "sanitized_input" => "scout the corridor, pick the lock, and push the door open",
        "danger_score" => 0, "reason" => "Compound exploration action.",
        "is_dm_query" => false }.to_json,

    "character sheet validator" =>
      { "consistent" => true, "reason" => nil, "dm_message" => nil, "allowed" => true }.to_json,

    "Dungeon Master for a Pathfinder" =>
      { "outcome" => "The corridor is quiet and empty.", "mutations" => {},
        "affected_contexts" => ["exploration"] }.to_json,

    "state tracker" =>
      { "context_updates" => {} }.to_json,

    "Dungeon Master narrator" =>
      { "narrative" => "The adventurer moves with purpose through the dungeon." }.to_json,

    "You estimate how much in-game time a Pathfinder" =>
      { "hours_elapsed" => 0.1, "encounter" => false, "journey_data" => nil }.to_json,

    "plot state manager" =>
      { "dm_brief" => "Player explored the area.", "clues_revealed" => [],
        "npc_reactions" => [], "milestones_reached" => [] }.to_json,

    "post-roll arbiter" =>
      { "outcome" => "The lock clicks open with a satisfying clunk.", "mutations" => {} }.to_json,
  }.freeze

  # ── OpenAI HTTP stub ───────────────────────────────────────────────────────
  WebMock.stub_request(:post, /api\.openai\.com/)
         .to_return do |request|
    body       = JSON.parse(request.body) rescue {}
    sys_msg    = Array(body["messages"]).find { |m| m["role"] == "system" }
    first_line = sys_msg&.[]("content").to_s.lines.first.to_s.strip

    match   = OPENAI_STEP_RESPONSES.find { |key, _| first_line.include?(key) }
    content = match ? match[1] : '{"result":"ok"}'

    {
      status: 200,
      body: {
        id:      "chatcmpl-stub",
        object:  "chat.completion",
        created: Time.now.to_i,
        model:   "gpt-4o-mini",
        choices: [{ index: 0, message: { role: "assistant", content: content },
                    finish_reason: "stop" }],
        usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 }
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    }
  end

  # ── Node evaluator HTTP stubs ──────────────────────────────────────────────
  # POST /moderate   — synchronous moderation for non-trusted users (see
  #                    DungeonMasterService#execute_prompt); without this stub,
  #                    Playwright would be the only flow that opens a real TCP
  #                    socket to EVALUATOR_URL before fan_out/sequential.
  # POST /fan_out  — beacons (all 6 domains in parallel) and roll_qualifier
  # POST /sequential — mech_eval (only affected domains, sequentially)
  #
  # Lock-pick detection: any user_message containing "lock" triggers a
  # Disable Device DC 15 roll for the exploration domain.

  evaluator_base = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")

  WebMock.stub_request(:post, "#{evaluator_base}/moderate")
         .to_return(
           status: 200,
           body: {
             "flagged" => false,
             "categories" => {},
             "category_scores" => {}
           }.to_json,
           headers: { "Content-Type" => "application/json" }
         )

  # Helper: build one evaluator result envelope.
  build_entry = lambda do |step, domain, parsed|
    { "raw_response"    => "stub",
      "parse_status"    => "success",
      "parsed_response" => parsed,
      "meta"            => { "step" => step, "domain" => domain },
      "usage"           => { "input_tokens" => 80, "output_tokens" => 30,
                             "reasoning_tokens" => 0, "total_tokens" => 110 },
      "model_used"      => "gpt-4o-mini",
      "duration_ms"     => 50,
      "request_body"    => {} }
  end

  fan_out_parsed_response = lambda do |step, domain, is_lock|
    case step
    when "roll_qualifier"
      { "qualifications" => [] }
    when "beacon"
      needs_mech = is_lock && domain == "exploration"
      {
        "affected" => domain == "exploration",
        "needs_mechanics" => needs_mech,
        "macro_significant" => false,
        "expand_scene" => false,
        "transition" => nil,
        "destination" => nil,
        "combatants" => [],
        "reasoning" => domain == "exploration" ? "Exploration" : "Not affected"
      }
    when "sanity_checker_world"
      { "consistent" => true, "reason" => nil, "dm_message" => nil }
    when "sanity_checker"
      { "allowed" => true, "reason" => nil }
    when "micro_context_update"
      { "context_updates" => {} }
    when "macro_narrative_update"
      { "story_summary" => "Stub summary." }
    when "meta_context_update"
      { "scene_summary" => "Stub scene summary.", "new_creatures" => [], "context_wishes" => [] }
    when "narrate"
      { "narrative" => "The adventurer moves with purpose through the dungeon." }
    when /\A[a-z]+_context_update\z/
      { "unchanged" => true, "context" => {} }
    else
      {}
    end
  end

  WebMock.stub_request(:post, "#{evaluator_base}/fan_out")
         .to_return do |request|
    body       = JSON.parse(request.body) rescue []
    first_step = body.dig(0, "meta", "step").to_s
    user_msg   = body.dig(0, "user_message").to_s.downcase
    is_lock    = user_msg.include?("lock")

    results = if first_step == "roll_qualifier"
      body.map { |p| build_entry.call("roll_qualifier", p.dig("meta", "domain"),
                                      "qualifications" => []) }
    else
      body.map do |p|
        st = p.dig("meta", "step").to_s
        domain = p.dig("meta", "domain")
        build_entry.call(st, domain, fan_out_parsed_response.call(st, domain, is_lock))
      end
    end

    { status: 200, body: results.to_json,
      headers: { "Content-Type" => "application/json" } }
  end

  WebMock.stub_request(:post, "#{evaluator_base}/sequential")
         .to_return do |request|
    body     = JSON.parse(request.body) rescue []
    user_msg = body.dig(0, "user_message").to_s.downcase
    is_lock  = user_msg.include?("lock")

    results = body.map do |p|
      domain = p.dig("meta", "domain")
      # Sequential mech_eval: combat domain uses CombatMechanicResolution when player_rolls is non-empty
      # (defense_kind + no model dc). Keep empty rolls here so default stubs need no combat_context.
      parsed = if is_lock && domain == "exploration"
        { "player_rolls"       => [{ "type" => "skill_check", "skill" => "Disable Device",
                                     "dc" => 15, "description" => "Pick the lock" }],
          "npc_actions"        => [],
          "consequences"       => [],
          "mechanical_summary" => "Player must beat DC 15 Disable Device" }
      else
        { "player_rolls" => [], "npc_actions" => [], "consequences" => [],
          "mechanical_summary" => "No mechanical interaction" }
      end
      build_entry.call("mechanical_evaluation", domain, parsed)
    end

    { status: 200, body: results.to_json,
      headers: { "Content-Type" => "application/json" } }
  end
end
