# frozen_string_literal: true

require "erb"

module DungeonMaster
  # Renders ERB prompt templates from app/services/dungeon_master/templates/.
  # Templates access their locals as instance variables (e.g. @domain).
  # Compiled templates are cached per-process; call reload! in dev/test
  # if editing templates without restarting.
  class PromptRenderer
    TEMPLATE_DIR = Rails.root.join("app/services/dungeon_master/templates")

    USER_MESSAGE_SEPARATOR = "---USER_MESSAGE---"

    def self.render(template_name, **locals)
      template = load_template(template_name)
      ctx = TemplateContext.new(**locals)
      template.result(ctx.send(:get_binding)).strip
    end

    # Returns [system_prompt, user_message]. Templates that include a
    # ---USER_MESSAGE--- separator define both halves; templates without
    # the separator return nil for user_message.
    def self.render_with_user_message(template_name, **locals)
      full = render(template_name, **locals)
      if full.include?(USER_MESSAGE_SEPARATOR)
        parts = full.split(USER_MESSAGE_SEPARATOR, 2)
        [parts[0].strip, parts[1].strip]
      else
        [full, nil]
      end
    end

    # Renders a partial template. Returns empty string if the file does not
    # exist, so callers can safely inject domain-specific fragments that may
    # or may not be defined.
    def self.render_partial(partial_path, **locals)
      path = TEMPLATE_DIR.join("#{partial_path}.text.erb")
      return "" unless path.exist?

      template = load_template(partial_path)
      ctx = TemplateContext.new(**locals)
      template.result(ctx.send(:get_binding)).strip
    end

    # Loads a JSON schema file from templates/schemas/<name>.json.
    # Returns the raw string so callers can embed it in prompts or parse it.
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
