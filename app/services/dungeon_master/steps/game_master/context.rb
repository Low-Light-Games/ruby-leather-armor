# frozen_string_literal: true

module DungeonMaster
  module Steps
    module GameMaster
      class Context
        attr_reader :intent_text,
                    :current_location_name,
                    :current_hour,
                    :adventure_day,
                    :light_conditions,
                    :npcs_at_location_summary,
                    :recent_dm_messages_slice,
                    :story_premise

        def initialize(intent_text:,
                       current_location_name:,
                       current_hour:,
                       adventure_day:,
                       light_conditions:,
                       npcs_at_location_summary:,
                       recent_dm_messages_slice:,
                       story_premise:)
          @intent_text              = intent_text
          @current_location_name    = current_location_name
          @current_hour             = current_hour
          @adventure_day            = adventure_day
          @light_conditions         = light_conditions
          @npcs_at_location_summary = npcs_at_location_summary
          @recent_dm_messages_slice = recent_dm_messages_slice
          @story_premise            = story_premise
        end
      end
    end
  end
end
