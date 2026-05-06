# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "GameMaster request_roll tool" do
  let(:user) { create(:user, :password_auth, :paid) }
  let(:adventure) { create(:adventure, user: user) }

  before do
    create(:adventure_sheet, adventure: adventure)
    create(:feature_flag, key: "gamemaster_orchestrator", mode: "bucketed",
                          bucketing_strategy: "granular", granular_user_ids: [user.id])
    sign_in(user)
    stub_openai_embeddings
    stub_evaluator_endpoints
    stub_telemetry_endpoints
  end

  it "no-tool path: GM emits empty tool_calls → single narrative message, turn ends" do
    stub_openai_chat_with(
      "intake" => -> { intake_clean("I look around the tavern.") },
      "Game Master" => -> { gm_response(narrative: "The tavern is sparsely lit; rain still hasn't let up.") }
    )

    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "I look around the tavern." }, as: :json
    end

    msgs = adventure.adventure_messages.where(role: "dm")
    expect(msgs.pluck(:message_type)).to eq(["narrative"])
    expect(msgs.last.content).to include("rain")
    expect(PlayLog.where(adventure_id: adventure.id, event_type: "request_roll_tool")).to be_empty
  end

  it "request_roll path: GM emits one tool call → narrative + roll_request both persist; loop is paused" do
    stub_openai_chat_with(
      "intake" => -> { intake_clean("I sneak past the guards.") },
      "Game Master" => -> {
        gm_response(
          narrative: "You press flat against the wall and ease forward, breath shallow.",
          tool_calls: [{ name: "request_roll", args: { intent_text: "I sneak past the guards." } }]
        )
      },
      "Pathfinder 1e rules adjudicator. The Game Master" => -> { request_roll_tool_response }
    )

    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "I sneak past the guards." }, as: :json
    end

    msgs = adventure.adventure_messages.where(role: "dm").order(:created_at)
    expect(msgs.pluck(:message_type)).to eq(%w[narrative roll_request])
    expect(msgs.first.content).to include("flat against the wall")

    roll_msg = msgs.last
    meta = roll_msg.metadata
    expect(meta["intent"]).to be_present
    expect(meta["intent"]["intention"]).to eq("I sneak past the guards.")
    expect(meta["roll_requests"]).to be_an(Array).and(have_attributes(length: 1))
    expect(meta["mechanical_summaries"]).to be_present

    # Loop persisted with paused status + lead_narrative recorded.
    loop_row = AdventureLoop.where(adventure_id: adventure.id).order(:created_at).last
    expect(loop_row.status).to eq("paused")
    expect(loop_row.data["lead_narrative"]).to include("flat against the wall")

    expect(PlayLog.where(adventure_id: adventure.id, event_type: "request_roll_tool")).to be_present
  end

  it "unsupported tool name: surfaces 'DM distracted' system message + PlayLog row captures the call" do
    stub_openai_chat_with(
      "intake" => -> { intake_clean("I cast Fireball.") },
      "Game Master" => -> {
        gm_response(
          narrative: "You begin tracing the runes for Fireball.",
          tool_calls: [{ name: "make_things_explode", args: {} }]
        )
      }
    )

    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "I cast Fireball." }, as: :json
    end

    fail_msg = adventure.adventure_messages.where(message_type: "narrative", role: "system").last
    expect(fail_msg).to be_present
    expect(fail_msg.content).to include("Dungeon Master is momentarily distracted")

    err_log = PlayLog.where(adventure_id: adventure.id, event_type: "game_master_tool_error").last
    expect(err_log).to be_present
    parsed = JSON.parse(err_log.parsed_response)
    expect(parsed["tool_calls"]).to be_present
    expect(parsed["error"]).to include("unknown tool: make_things_explode")
  end

  it "round-trip resume: roll submitted → legacy Mechanic + Narrate path produces final narrative + applies mutations" do
    stub_openai_chat_with(
      "intake" => ->(user_msg) { intake_clean(user_msg) },
      "Game Master" => -> {
        gm_response(
          narrative: "You weave a story for the guard about a delivery.",
          tool_calls: [{ name: "request_roll", args: { intent_text: "I lie to the guard." } }]
        )
      },
      "Pathfinder 1e rules adjudicator. The Game Master" => -> { request_roll_tool_response(skill: "Bluff", dc: 15) },
      "post-roll arbiter" => -> {
        { outcome: "The guard accepts the lie and waves the player past.", mutations: { player: { hp_change: 0 } } }
      },
      "Dungeon Master narrator" => -> { { narrative: "The guard squints, then waves you through." } },
      "estimate how much in-game time" => -> { { hours_elapsed: 0.05, encounter: false, journey_data: nil } }
    )

    # Initial request — pauses for rolls
    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "I lie to the guard." }, as: :json
    end

    pending = adventure.adventure_messages.where(message_type: "roll_request").last
    expect(pending).to be_present
    request_id = pending.metadata["roll_requests"].first["request_id"]

    # Player submits roll — resume should run the legacy chain
    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages/roll",
           params: { roll_value: 18, request_id: request_id, resolution_method: "roll" }, as: :json
    end

    # The resume path eventually persists a final narrative AdventureMessage
    final = adventure.adventure_messages.where(role: "dm", message_type: "narrative").order(:created_at).last
    expect(final).to be_present
    # Either GM lead OR resume narrative is the latest narrative — assert resume got further than the lead
    resolved_loop = AdventureLoop.where(adventure_id: adventure.id).order(:created_at).last
    expect(resolved_loop.status).to eq("resolved")
    expect(PlayLog.where(adventure_id: adventure.id, event_type: "mechanic")).to be_present
  end

  private

  def intake_clean(content)
    { sanitized_input: content, danger_score: 0, reason: nil }
  end

  def gm_response(narrative:, tool_calls: [], adventure_ended: false, player_dead: false)
    {
      reasoning: "test plan",
      adventure_ended: adventure_ended,
      player_dead: player_dead,
      tool_calls: tool_calls,
      narrative: narrative
    }
  end

  def request_roll_tool_response(skill: "Stealth", dc: 15)
    {
      type: "skill_check",
      skill: skill,
      save: nil,
      dc: dc,
      description: "#{skill} check, DC #{dc}",
      take_10_eligible: false,
      take_20_eligible: false,
      situational_modifiers: [],
      rule_slug: skill.downcase,
      mechanical_summary: "The player attempts a #{skill} check.",
      reasoning: "Closest rule fit."
    }
  end

  def stub_openai_chat_with(branches)
    WebMock.stub_request(:post, %r{api\.openai\.com/v1/chat}).to_return do |req|
      body = JSON.parse(req.body) rescue {}
      sys = Array(body["messages"]).find { |m| m["role"] == "system" }&.dig("content").to_s
      user_msg = Array(body["messages"]).find { |m| m["role"] == "user" }&.dig("content").to_s
      key = branches.keys.find { |k| sys.include?(k) }
      content = if key
                  resp = branches[key]
                  (resp.arity == 1 ? resp.call(user_msg) : resp.call).to_json
                else
                  '{"result":"ok"}'
                end
      {
        status: 200,
        body: {
          id: "chatcmpl-stub", object: "chat.completion", created: Time.now.to_i, model: "gpt-5-nano",
          choices: [{ index: 0, message: { role: "assistant", content: content }, finish_reason: "stop" }],
          usage: { prompt_tokens: 100, completion_tokens: 30, total_tokens: 130 }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      }
    end
  end

  def stub_openai_embeddings
    WebMock.stub_request(:post, %r{api\.openai\.com/v1/embeddings}).to_return(
      status: 200,
      body: {
        "data" => [{ "index" => 0, "embedding" => Array.new(1536, 0.0), "object" => "embedding" }],
        "usage" => { "prompt_tokens" => 4, "total_tokens" => 4 }
      }.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  def stub_evaluator_endpoints
    WebMock.stub_request(:post, %r{/moderate}).to_return(
      status: 200,
      body: { "flagged" => false, "categories" => {}, "category_scores" => {} }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    fan_out_response = lambda do |request|
      body = JSON.parse(request.body) rescue []
      results = body.map do |p|
        step = p.dig("meta", "step").to_s
        parsed = case step
                 when "sanity_checker_world" then { "consistent" => true, "reason" => nil, "dm_message" => nil }
                 when "sanity_checker" then { "allowed" => true, "reason" => nil }
                 when "combat_context_update" then { "combat_context" => {}, "new_creatures" => [] }
                 when "loremaster" then { "facts" => [], "invalidates" => [], "reasoning" => "stub" }
                 when "narrate" then { "narrative" => "The guard squints, then waves you through." }
                 else {}
                 end
        {
          "raw_response" => "stub",
          "parse_status" => "success",
          "parsed_response" => parsed,
          "meta" => { "step" => step },
          "usage" => { "input_tokens" => 80, "output_tokens" => 30, "reasoning_tokens" => 0, "total_tokens" => 110 },
          "model_used" => "gpt-4o-mini",
          "duration_ms" => 50,
          "request_body" => {}
        }
      end
      { status: 200, body: results.to_json, headers: { "Content-Type" => "application/json" } }
    end

    WebMock.stub_request(:post, %r{/fan_out}).to_return(&fan_out_response)
  end

  def stub_telemetry_endpoints
    WebMock.stub_request(:post, %r{api\.axiom\.co}).to_return(status: 200, body: "{}")
    WebMock.stub_request(:put, %r{s3\.amazonaws\.com}).to_return(status: 200, body: "")
  end
end
