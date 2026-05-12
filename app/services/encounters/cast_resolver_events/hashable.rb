# frozen_string_literal: true

module Encounters
  module CastResolverEvents
    module Hashable
      def to_h
        instance_variables.each_with_object({}) do |ivar, hash|
          hash[ivar.to_s.delete_prefix("@").to_sym] = instance_variable_get(ivar)
        end
      end
    end
  end
end
