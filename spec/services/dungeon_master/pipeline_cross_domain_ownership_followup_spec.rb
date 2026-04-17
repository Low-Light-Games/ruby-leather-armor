# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster cross-domain ownership follow-ups", type: :service do
  include_context "with mocked ai"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 10, max_hp: 10, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 14, wisdom: 10, charisma: 10,
      race: "human", character_class: "wizard", level: 1)
  end
  let!(:goblin) do
    CreatureSheet.create!(
      adventure: adventure,
      name: "Goblin", creature_type: "monster", origin: "template",
      hp: 8, max_hp: 8, constitution: 10,
      strength: 10, dexterity: 14, intelligence: 6, wisdom: 8, charisma: 8,
      derived_stats: { "touch_ac" => 12 }
    )
  end
  let(:pipeline) { build_pipeline(adventure) }
  let(:evaluator_base) { ENV.fetch("EVALUATOR_URL", "http://evaluator:3001") }

  before do
    WebMock.enable!
    WebMock.allow_net_connect!(allow_localhost: true)
  end

  after do
    WebMock.reset!
    WebMock.disable!
  end

  it "keeps pure spellcasting out of inventory routing when combat already owns the action" do
    adventure.update!(
      combat_context: {
        "active" => true,
        "participants" => [
          { "name" => "Player", "type" => "player", "initiative" => 8, "hp" => 10, "max_hp" => 10, "conditions" => [] },
          { "name" => "Goblin", "type" => "npc", "initiative" => 17, "hp" => 8, "max_hp" => 8, "conditions" => [], "creature_sheet_id" => goblin.id }
        ],
        "turn_order" => ["Goblin", "Player"],
        "current_turn" => "Goblin"
      }
    )

    sequential_domains = []

    stub_beacon_fan_out do |body|
      body.map do |p|
        domain = p.dig("meta", "domain")
        parsed = {
          "affected" => false,
          "macro_significant" => false,
          "expand_scene" => false,
          "transition" => nil,
          "destination" => nil,
          "combatants" => [],
          "reasoning" => "out of scope"
        }
        evaluator_entry("beacon", domain, "parsed_response" => parsed)
      end
    end

    WebMock.stub_request(:post, "#{evaluator_base}/sequential").to_return do |request|
      body = JSON.parse(request.body)
      sequential_domains = body.map { |p| p.dig("meta", "domain") }

      results = body.map do |p|
        evaluator_entry("mechanical_evaluation", p.dig("meta", "domain"), "parsed_response" => {
          "player_rolls" => [
            {
              "type" => "attack_roll",
              "target" => "Goblin",
              "defense_kind" => "touch_ac",
              "description" => "Ranged touch spell attack",
              "damage" => "1d3",
              "damage_type" => "cold"
            }
          ],
          "npc_actions" => [],
          "consequences" => [],
          "mechanical_summary" => "Combat attack roll owned by combat."
        })
      end

      { status: 200, body: results.to_json, headers: { "Content-Type" => "application/json" } }
    end

    intent, evaluations = pipeline.send(:run_parallel_evaluation, "I cast Ray of Frost at the goblin.")
    merged = pipeline.send(:merge_mechanical_evaluations_and_prepare_rolls, evaluations)

    expect(intent[:affected_contexts]).to eq(["combat"])
    expect(sequential_domains).to eq(["combat"])
    expect(merged[:player_rolls]).to contain_exactly(include(domain: "combat", type: "attack_roll", dc: 12))
  end

  it "keeps stealth roll generation on exploration when the action is stealthy" do
    sequential_domains = []

    stub_beacon_fan_out do |body|
      body.map do |p|
        domain = p.dig("meta", "domain")
        parsed = if domain == "exploration"
                   {
                     "affected" => true,
                     "macro_significant" => false,
                     "expand_scene" => false,
                     "transition" => nil,
                     "destination" => nil,
                     "combatants" => [],
                     "reasoning" => "Player is sneaking past nearby observers."
                   }
                 else
                   {
                     "affected" => false,
                     "macro_significant" => false,
                     "expand_scene" => false,
                     "transition" => nil,
                     "destination" => nil,
                     "combatants" => [],
                     "reasoning" => "not affected"
                   }
                 end
        evaluator_entry("beacon", domain, "parsed_response" => parsed)
      end
    end

    WebMock.stub_request(:post, "#{evaluator_base}/sequential").to_return do |request|
      body = JSON.parse(request.body)
      sequential_domains = body.map { |p| p.dig("meta", "domain") }

      results = body.map do |p|
        parsed = if p.dig("meta", "domain") == "exploration"
                   {
                     "player_rolls" => [
                       {
                         "type" => "skill_check",
                         "skill" => "Stealth",
                         "dc" => 15,
                         "description" => "Sneak past the goblins unnoticed"
                       }
                     ],
                     "npc_actions" => [],
                     "consequences" => [],
                     "mechanical_summary" => "Stealth check opposed by nearby observers."
                   }
                 else
                   {
                     "player_rolls" => [],
                     "npc_actions" => [],
                     "consequences" => [],
                     "mechanical_summary" => "No mechanical interaction."
                   }
                 end

        evaluator_entry("mechanical_evaluation", p.dig("meta", "domain"), "parsed_response" => parsed)
      end

      { status: 200, body: results.to_json, headers: { "Content-Type" => "application/json" } }
    end

    intent, evaluations = pipeline.send(:run_parallel_evaluation, "I sneak past the goblins without being noticed.")
    merged = pipeline.send(:merge_mechanical_evaluations_and_prepare_rolls, evaluations)

    expect(intent[:affected_contexts]).to eq(["exploration"])
    expect(sequential_domains).to eq(["exploration"])
    expect(merged[:player_rolls]).to contain_exactly(
      include(domain: "exploration", type: "skill_check", skill: "Stealth", dc: 15)
    )
  end

  private

  def stub_beacon_fan_out(&block)
    WebMock.stub_request(:post, "#{evaluator_base}/fan_out").to_return do |request|
      body = JSON.parse(request.body)
      first_step = body.dig(0, "meta", "step").to_s

      results = if first_step == "roll_qualifier"
        body.map do |p|
          evaluator_entry("roll_qualifier", p.dig("meta", "domain"), "parsed_response" => { "qualifications" => [] })
        end
      else
        block.call(body)
      end

      { status: 200, body: results.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  def evaluator_entry(step, domain, overrides = {})
    {
      "raw_response" => "stub",
      "parse_status" => "success",
      "parsed_response" => {},
      "meta" => { "step" => step, "domain" => domain },
      "usage" => { "input_tokens" => 80, "output_tokens" => 30, "reasoning_tokens" => 0, "total_tokens" => 110 },
      "model_used" => "gpt-4o-mini",
      "duration_ms" => 50,
      "request_body" => {}
    }.merge(overrides)
  end
end
