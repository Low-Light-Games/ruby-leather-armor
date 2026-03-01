# frozen_string_literal: true

require "erb"

module DungeonMaster
  # Renders ERB prompt templates from app/services/dungeon_master/templates/.
  # Templates access their locals as instance variables (e.g. @domain).
  # Compiled templates are cached per-process; call reload! in dev/test
  # if editing templates without restarting.
  class PromptRenderer
    TEMPLATE_DIR = Rails.root.join("app/services/dungeon_master/templates")

    def self.render(template_name, **locals)
      template = load_template(template_name)
      ctx = TemplateContext.new(**locals)
      template.result(ctx.send(:get_binding)).strip
    end

    def self.reload!
      @templates = nil
    end

    def self.load_template(name)
      @templates ||= {}
      @templates[name] ||= begin
        path = TEMPLATE_DIR.join("#{name}.text.erb")
        ERB.new(path.read, trim_mode: "-")
      end
    end

    class TemplateContext
      def initialize(**attrs)
        attrs.each { |k, v| instance_variable_set(:"@#{k}", v) }
      end

      private

      def get_binding
        binding
      end
    end

    private_class_method :load_template
  end
end
