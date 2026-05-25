# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "GameMaster pipeline branch" do
  let(:user) { create(:user, :password_auth, :paid) }
  let(:adventure) { create(:adventure, user: user) }

  before do
    create(:adventure_sheet, adventure: adventure)
    sign_in(user)
  end

  it "branches to GameMaster when the adventure opts in, persists the narrative" do
    adventure.update!(use_gamemaster_orchestrator: true)

    stub_openai_chat_with(branch_for: ->(system_prompt) {
      if system_prompt.start_with?("You are the intake filter")
        { sanitized_input: "I look around the tavern.", danger_score: 0, reason: nil }
      elsif system_prompt.start_with?("You are the Game Master")
        {
          reasoning: "Establish atmosphere.",
          adventure_ended: false,
          player_dead: false,
          narrative: "You scan the tavern. The barkeep nods, eyes wary."
        }
      else
        { result: "ok" }
      end
    })
    stub_openai_embeddings
    stub_evaluator_endpoints

    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "I look around the tavern." }, as: :json
    end
    expect(response).to have_http_status(:accepted)

    narrative = adventure.adventure_messages.dm_narration.last
    expect(narrative).to be_present
    expect(narrative.content).to include("barkeep")

    plan_log = PlayLog.find_by(adventure_id: adventure.id, event_type: "game_master_plan")
    expect(plan_log).to be_present
    parsed = JSON.parse(plan_log.parsed_response)
    expect(parsed["narrative_chars"]).to be_positive
    expect(parsed["adventure_ended"]).to be(false)
  end

  it "stays on the legacy phase chain when the adventure has not opted in" do
    # Toggle is OFF by default. The GameMaster step must not run.
    expect(PlayerTurn::Steps::GameMaster).not_to receive(:instance_method).with(:run_game_master) # smoke-only
    # Real assertion: no game_master_plan PlayLog row gets written.
    stub_openai_chat_with(branch_for: ->(_sys) { { sanitized_input: "noop", danger_score: 0, reason: nil } })
    stub_openai_embeddings
    stub_evaluator_endpoints

    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "noop" }, as: :json
    end

    expect(PlayLog.where(adventure_id: adventure.id, event_type: "game_master_plan")).to be_empty
  end

  it "stays on the legacy phase chain when combat is active even with the toggle on" do
    adventure.update!(use_gamemaster_orchestrator: true, combat_context: { "active" => true })

    stub_openai_chat_with(branch_for: ->(_sys) { { sanitized_input: "noop", danger_score: 0, reason: nil } })
    stub_openai_embeddings
    stub_evaluator_endpoints

    perform_enqueued_jobs do
      post "/adventures/#{adventure.id}/messages",
           params: { content: "I swing!" }, as: :json
    end

    expect(PlayLog.where(adventure_id: adventure.id, event_type: "game_master_plan")).to be_empty
  end

  private

  def stub_openai_chat_with(branch_for:)
    WebMock.stub_request(:post, %r{api\.openai\.com/v1/chat}).to_return do |req|
      body = JSON.parse(req.body) rescue {}
      sys = Array(body["messages"]).find { |m| m["role"] == "system" }&.dig("content").to_s
      content = branch_for.call(sys).to_json
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
    WebMock.stub_request(:post, %r{/fan_out}).to_return(
      status: 200, body: "[]", headers: { "Content-Type" => "application/json" }
    )
    WebMock.stub_request(:post, %r{api\.axiom\.co}).to_return(status: 200, body: "{}")
    WebMock.stub_request(:put, %r{s3\.amazonaws\.com}).to_return(status: 200, body: "")
  end
end
