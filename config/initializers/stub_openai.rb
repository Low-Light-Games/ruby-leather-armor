# frozen_string_literal: true

# When STUB_OPENAI=true is set (e.g. during Playwright E2E runs), intercept
# all outbound AI calls at the HTTP layer and return canned responses so tests
# never depend on a real API key, network access, or a running evaluator.
if ENV['STUB_OPENAI'].present?
  require 'webmock'
  WebMock.enable!
  WebMock.allow_net_connect!(allow_localhost: true)

  # ── OpenAI response map ────────────────────────────────────────────────────
  # Matched against the first line of the system prompt.
  # The sequencer always returns 3 actions for the E2E compound-action scenario.
  OPENAI_STEP_RESPONSES = {
    'compound action detector' =>
      { 'actions' => ['scout the corridor', 'pick the lock', 'push the door open'] }.to_json,

    'intake filter' =>
      { 'sanitized_input' => 'scout the corridor, pick the lock, and push the door open',
        'danger_score' => 0, 'reason' => 'Compound exploration action.' }.to_json,

    'character sheet validator' =>
      { 'consistent' => true, 'reason' => nil, 'dm_message' => nil, 'allowed' => true }.to_json,

    'Dungeon Master for a Pathfinder' =>
      { 'outcome' => 'The corridor is quiet and empty.', 'mutations' => {},
        'affected_contexts' => ['exploration'] }.to_json,

    'state tracker' =>
      { 'context_updates' => {} }.to_json,

    'Dungeon Master narrator' =>
      { 'narrative' => 'The adventurer moves with purpose through the dungeon.' }.to_json,

    'You estimate how much in-game time a Pathfinder' =>
      { 'hours_elapsed' => 0.1, 'encounter' => false, 'journey_data' => nil }.to_json,

    'plot state manager' =>
      { 'dm_brief' => 'Player explored the area.', 'clues_revealed' => [],
        'npc_reactions' => [], 'milestones_reached' => [] }.to_json,

    'post-roll arbiter' =>
      { 'outcome' => 'The lock clicks open with a satisfying clunk.', 'mutations' => {} }.to_json
  }.freeze

  # RollRequest / CombatRollRequest stubs — both steps hit OpenAI
  # directly with their own prompts; lock-pick detection branches the
  # response so existing E2E expectations keep passing.
  ROLL_REQUEST_NO_ROLL = lambda do |intention, mechanical_summary|
    {
      'needs_roll' => false,
      'no_roll_reason' => 'no rule fits',
      'roll' => nil,
      'affected_domains' => ['exploration'],
      'expand_scene' => false,
      'transition' => nil,
      'combatants' => [],
      'destination' => nil,
      'consequences' => [],
      'ability_use_claimed' => nil,
      'mechanical_summary' => mechanical_summary,
      'reasoning' => "Stubbed: #{intention}"
    }.to_json
  end

  ROLL_REQUEST_LOCK_PICK = lambda do
    {
      'needs_roll' => true,
      'no_roll_reason' => nil,
      'roll' => {
        'type' => 'skill_check',
        'skill' => 'Disable Device',
        'save' => nil,
        'dc' => 15,
        'description' => 'Pick the lock',
        'take_10_eligible' => false,
        'take_20_eligible' => false,
        'situational_modifiers' => [],
        'rule_slug' => 'disable_device'
      },
      'affected_domains' => ['exploration'],
      'expand_scene' => false,
      'transition' => nil,
      'combatants' => [],
      'destination' => nil,
      'consequences' => [],
      'ability_use_claimed' => nil,
      'mechanical_summary' => 'Player must beat DC 15 Disable Device',
      'reasoning' => 'Lock pick action'
    }.to_json
  end

  COMBAT_ROLL_REQUEST_NO_ROLL = lambda do |intention|
    {
      'needs_roll' => false,
      'no_roll_reason' => 'positioning only',
      'roll' => nil,
      'action_cost' => 'free',
      'affected_domains' => ['combat'],
      'consequences' => [],
      'mechanical_summary' => "Stubbed combat free-text: #{intention}",
      'reasoning' => 'Stub fallback'
    }.to_json
  end

  # ── OpenAI HTTP stub ───────────────────────────────────────────────────────
  parse_openai_request = lambda do |request|
    body = begin
      JSON.parse(request.body)
    rescue StandardError
      {}
    end
    sys_msg = Array(body['messages']).find { |m| m['role'] == 'system' }
    user_msg = Array(body['messages']).find { |m| m['role'] == 'user' }&.[]('content').to_s
    [sys_msg&.[]('content').to_s.lines.first.to_s.strip, user_msg]
  end

  pick_openai_content = lambda do |first_line, user_msg|
    if first_line.include?('Pathfinder 1e combat rules adjudicator')
      COMBAT_ROLL_REQUEST_NO_ROLL.call(user_msg)
    elsif first_line.include?('Pathfinder 1e rules adjudicator')
      if user_msg.downcase.include?('lock')
        ROLL_REQUEST_LOCK_PICK.call
      else
        ROLL_REQUEST_NO_ROLL.call(user_msg, 'No mechanical interaction')
      end
    else
      match = OPENAI_STEP_RESPONSES.find { |key, _| first_line.include?(key) }
      match ? match[1] : '{"result":"ok"}'
    end
  end

  build_openai_response = lambda do |content|
    {
      status: 200,
      body: {
        id: 'chatcmpl-stub', object: 'chat.completion', created: Time.now.to_i, model: 'gpt-4o-mini',
        choices: [{ index: 0, message: { role: 'assistant', content: content }, finish_reason: 'stop' }],
        usage: { prompt_tokens: 10, completion_tokens: 10, total_tokens: 20 }
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    }
  end

  WebMock.stub_request(:post, /api\.openai\.com/).to_return do |request|
    first_line, user_msg = parse_openai_request.call(request)
    build_openai_response.call(pick_openai_content.call(first_line, user_msg))
  end

  # Registered after the broad chat stub above — WebMock matches the
  # most-recently-declared stub first.
  WebMock.stub_request(:post, %r{api\.openai\.com/v1/embeddings}).to_return do |request|
    body = begin
      JSON.parse(request.body)
    rescue StandardError
      {}
    end
    inputs = Array(body['input'])
    inputs = [body['input'].to_s] if inputs.empty? && body['input']
    dim = body['dimensions'].to_i.positive? ? body['dimensions'].to_i : 1536
    data = inputs.each_with_index.map do |_text, idx|
      { 'index' => idx, 'embedding' => Array.new(dim, 0.0), 'object' => 'embedding' }
    end
    {
      status: 200,
      body: {
        'object' => 'list', 'data' => data,
        'model' => body['model'] || 'text-embedding-3-small',
        'usage' => { 'prompt_tokens' => inputs.length * 2, 'total_tokens' => inputs.length * 2 }
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    }
  end

  # ── Node evaluator HTTP stubs ──────────────────────────────────────────────
  # POST /moderate   — synchronous moderation for non-trusted users.
  # POST /fan_out    — sanity gate, narrative phase (narrate + context updates),
  #                    micro-context updates, NPC actions in WorldTurn.

  evaluator_base = ENV.fetch('EVALUATOR_URL', 'http://evaluator:3001')

  WebMock.stub_request(:post, "#{evaluator_base}/moderate")
         .to_return(
           status: 200,
           body: {
             'flagged' => false,
             'categories' => {},
             'category_scores' => {}
           }.to_json,
           headers: { 'Content-Type' => 'application/json' }
         )

  build_entry = lambda do |step, domain, parsed|
    { 'raw_response' => 'stub',
      'parse_status' => 'success',
      'parsed_response' => parsed,
      'meta' => { 'step' => step, 'domain' => domain },
      'usage' => { 'input_tokens' => 80, 'output_tokens' => 30,
                   'reasoning_tokens' => 0, 'total_tokens' => 110 },
      'model_used' => 'gpt-4o-mini',
      'duration_ms' => 50,
      'request_body' => {} }
  end

  fan_out_parsed_response = lambda do |step|
    case step
    when 'sanity_checker_world' then { 'consistent' => true, 'reason' => nil, 'dm_message' => nil }
    when 'sanity_checker' then { 'allowed' => true, 'reason' => nil }
    when 'macro_narrative_update' then { 'story_summary' => 'Stub summary.' }
    when 'combat_context_update' then { 'combat_context' => {}, 'new_creatures' => [] }
    when 'loremaster' then { 'facts' => [], 'invalidates' => [], 'reasoning' => 'Stub.' }
    when 'narrate' then { 'narrative' => 'The adventurer moves with purpose through the dungeon.' }
    else
      {}
    end
  end

  WebMock.stub_request(:post, "#{evaluator_base}/fan_out")
         .to_return do |request|
    body = begin
      JSON.parse(request.body)
    rescue StandardError
      []
    end

    results = body.map do |p|
      st = p.dig('meta', 'step').to_s
      domain = p.dig('meta', 'domain')
      build_entry.call(st, domain, fan_out_parsed_response.call(st))
    end

    { status: 200, body: results.to_json,
      headers: { 'Content-Type' => 'application/json' } }
  end
end
