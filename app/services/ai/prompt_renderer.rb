# frozen_string_literal: true

require "erb"

module Ai
  class PromptRenderer
    TEMPLATE_DIR = Rails.root.join("app/services/dungeon_master/templates")

    USER_MESSAGE_SEPARATOR = "---USER_MESSAGE---"

    def self.render(template_name, **locals)
      template = load_template(template_name)
      ctx = TemplateContext.new(**locals)
      template.result(ctx.send(:get_binding)).strip
    end

    def self.render_with_user_message(template_name, **locals)
      full = render(template_name, **locals)
      unless full.include?(USER_MESSAGE_SEPARATOR)
        raise ArgumentError, "Template #{template_name.inspect} does not define #{USER_MESSAGE_SEPARATOR}"
      end

      parts = full.split(USER_MESSAGE_SEPARATOR, 2)
      [parts[0].strip, parts[1].strip]
    end

    def self.render_partial(partial_path, **locals)
      path = TEMPLATE_DIR.join("#{partial_path}.text.erb")
      return "" unless path.exist?

      template = load_template(partial_path)
      ctx = TemplateContext.new(**locals)
      template.result(ctx.send(:get_binding)).strip
    end

    def self.load_schema(name)
      @schemas ||= {}
      @schemas[name] ||= TEMPLATE_DIR.join("schemas", "#{name}.json").read
    end

    def self.reload!
      @templates = nil
      @schemas = nil
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
