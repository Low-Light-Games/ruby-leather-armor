# frozen_string_literal: true

module DungeonMaster
  module Steps
    module ContextUpdate
      class DomainContextResultParser
        def initialize(domain_identifier:, raw_domain_result:)
          @domain_identifier = domain_identifier.to_s
          @raw_domain_result = raw_domain_result
        end

        def pre_normalized?
          return false unless @raw_domain_result.is_a?(Hash)

          @raw_domain_result.key?("context") ||
            @raw_domain_result.key?(:context) ||
            @raw_domain_result.key?("unchanged") ||
            @raw_domain_result.key?(:unchanged)
        end

        def normalized_result
          normalized_domain_result = @raw_domain_result.is_a?(Hash) ? @raw_domain_result.deep_stringify_keys : {}
          {
            "unchanged" => normalized_domain_result["unchanged"] == true,
            "context" => extract_context_payload(normalized_domain_result)
          }
        end

        private

        def extract_context_payload(normalized_domain_result)
          domain_context_identifier = "#{@domain_identifier}_context"
          return normalized_domain_result["context"] if normalized_domain_result.key?("context")
          return normalized_domain_result[domain_context_identifier] if normalized_domain_result.key?(domain_context_identifier)
          return normalized_domain_result[@domain_identifier] if normalized_domain_result.key?(@domain_identifier)
          return normalized_domain_result if normalized_domain_result.present? && !normalized_domain_result.key?("unchanged")

          nil
        end
      end
    end
  end
end
