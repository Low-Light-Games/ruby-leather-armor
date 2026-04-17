# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DungeonMaster cross-domain ownership", type: :service do
  include_context "with mocked ai"

  let(:story) { create(:story) }
  let(:user) { create(:user) }
  let(:adventure) { create(:adventure, user: user, story: story) }
  let!(:adv_sheet) do
    create(:adventure_sheet, adventure: adventure,
      hp: 10, max_hp: 10, constitution: 10,
      strength: 10, dexterity: 10, intelligence: 14, wisdom: 10, charisma: 10,
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
  let!(:ray_of_frost) do
    SpellDefinition.create!(
      id: "ray_of_frost",
      name: "Ray of Frost",
      school: "evocation",
      class_levels: { "wizard" => 0 },
      components: %w[V S],
      casting_time: "1 standard action",
      range: "close",
      duration: "instantaneous",
      saving_throw: "none",
      spell_resistance: false,
      effects: [{ "type" => "damage", "dice" => "1d3", "damageType" => "cold" }],
      summary: "Ranged touch attack deals 1d3 cold damage."
    )
  end

  before do
    adv_sheet.adventure_sheet_spells.create!(spell_id: ray_of_frost.id, storage_type: "spellbook")
    WebMock.enable!
    WebMock.allow_net_connect!(allow_localhost: true)

    evaluator_base = ENV.fetch("EVALUATOR_URL", "http://evaluator:3001")

    WebMock.stub_request(:post, "#{evaluator_base}/fan_out").to_return do |request|
      body = JSON.parse(request.body)
      first_step = body.dig(0, "meta", "step").to_s

      results = if first_step == "roll_qualifier"
        body.map do |p|
          domain = p.dig("meta", "domain")
          evaluator_entry("roll_qualifier", domain, "parsed_response" => { "qualifications" => [] })
        end
      else
        body.map do |p|
          domain = p.dig("meta", "domain")
          parsed = if domain == "inventory"
                     {
                       "affected" => true,
                       "macro_significant" => false,
                       "expand_scene" => false,
                       "transition" => nil,
                       "destination" => nil,
                       "combatants" => [],
                       "reasoning" => "bad inventory beacon"
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

      { status: 200, body: results.to_json, headers: { "Content-Type" => "application/json" } }
    end

    WebMock.stub_request(:post, "#{evaluator_base}/sequential").to_return do |request|
      body = JSON.parse(request.body)
      results = body.map do |p|
        domain = p.dig("meta", "domain")
        parsed = case domain
                 when "combat"
                   {
                     "player_rolls" => [
                       {
                         "type" => "attack_roll",
                         "attack_option_id" => "spell:ray_of_frost:ranged_touch",
                         "target" => "Goblin",
                         "description" => "Ranged touch spell attack"
                       }
                     ],
                     "npc_actions" => [],
                     "consequences" => [],
                     "mechanical_summary" => "Combat attack roll owned by combat."
                   }
                 when "inventory"
                   {
                     "player_rolls" => [
                       {
                         "type" => "attack_roll",
                         "dc" => 16,
                         "description" => "Ray of Frost attack against the goblin",
                         "damage" => "1d3",
                         "damage_type" => "cold",
                         "target" => "goblin"
                       }
                     ],
                     "npc_actions" => [],
                     "consequences" => [],
                     "mechanical_summary" => "Bad duplicate inventory attack roll."
                   }
                 else
                   {
                     "player_rolls" => [],
                     "npc_actions" => [],
                     "consequences" => [],
                     "mechanical_summary" => "No mechanical interaction."
                   }
                 end

        evaluator_entry("mechanical_evaluation", domain, "parsed_response" => parsed)
      end

      { status: 200, body: results.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  after do
    WebMock.reset!
    WebMock.disable!
  end

  it "keeps only the combat attack roll when inventory is incorrectly affected during active combat" do
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

    allow(pipeline.instance_variable_get(:@log)).to receive(:play_log!)

    intent, evaluations = pipeline.send(:run_parallel_evaluation, "I cast Ray of Frost again, at the first goblin.")
    merged = pipeline.send(:merge_mechanical_evaluations_and_prepare_rolls, evaluations)

    expect(intent[:affected_contexts]).to include("combat", "inventory")
    expect(merged[:player_rolls]).to contain_exactly(include(domain: "combat", type: "attack_roll", dc: 12))
    expect(pipeline.instance_variable_get(:@log)).to have_received(:play_log!).with(
      "ownership_guard",
      /Dropped inventory roll/,
      parsed_response: hash_including(domain: "inventory", violation: "forbidden_type")
    )
  end

  it "locks the traversal and exploration prompt ownership around stealth" do
    traversal = DungeonMaster::PromptRenderer.render_partial("beacon/_traversal")
    exploration = DungeonMaster::PromptRenderer.render_partial("beacon/_exploration")
    inventory = DungeonMaster::PromptRenderer.render_partial("beacon/_inventory")

    expect(traversal).to include("Traversal does NOT own stealth")
    expect(exploration).to include("Exploration also owns stealth-style field actions")
    expect(inventory).to include("concrete inventory state")
    expect(inventory).not_to include("spellcasting")
  end

  private

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
