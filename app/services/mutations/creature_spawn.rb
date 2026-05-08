# frozen_string_literal: true

module Mutations
  class CreatureSpawn
    def initialize(adventure:, sheet:, log:, ai:, config:, on_error:)
      @adventure = adventure
      @sheet = sheet
      @log = log
      @ai = ai
      @config = config
      @on_error = on_error
    end

    def call(creature_names)
      factory = CreatureFactory.new(@adventure,
        sheet:  @sheet,
        log:    @log,
        ai:     @ai,
        config: @config
      )

      CoercedMutationArray.coerce(creature_names, field: "new_creatures", log: @log).each do |name|
        factory.create_for_name(name)
      end
    rescue StandardError => e
      @on_error.call("new_creatures", e)
    end
  end
end
