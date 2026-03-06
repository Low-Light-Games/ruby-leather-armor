module ApplicationHelper
  def log_row_class(log)
    content = log.content.downcase
    if content.include?("was malicious")
      "log-malicious"
    elsif content.include?("had to be sanitized")
      "log-sanitized"
    elsif content.include?("passed the sanitization")
      "log-passed"
    elsif content.include?("dm responded") || content.include?("dm reasoning")
      "log-dm-response"
    else
      ""
    end
  end

  def ai_log_status_class(status)
    case status
    when "success" then "status-success"
    when "parse_fallback" then "status-fallback"
    when "parse_error", "api_error", "token_budget_exceeded" then "status-error"
    else ""
    end
  end

  def ai_log_type_badge_class(call_type)
    case call_type
    when "triage", "sanitize", "classify", "dispatcher", "beacon", "capability_guardrail", "sanity_checker", "sanity_checker_world", "chronicler" then "type-triage"
    when "sequencer", "intent", "player_interpreter" then "type-intent"
    when "mechanical_evaluation", "roll_qualifier" then "type-ruling"
    when "ruling", "verdict"     then "type-evaluate"
    when "time_keeper"           then "type-ctx"
    when "narrate"               then "type-narrate"
    when "dm_query"              then "type-dm-query"
    when "micro_context_update"  then "type-ctx"
    when "macro_narrative_update" then "type-ctx"
    when "edge_pipeline"         then "type-narrate"
    else "type-default"
    end
  end

  def pipeline_step_title(log)
    title = log.call_type.humanize
    if log.call_type == "beacon" && log.prompt_summary =~ /\[(\w+)\]/
      title = "#{title} — #{$1}"
    end
    title
  end

  def format_duration_ms(ms)
    return "—" unless ms
    ms > 1000 ? "#{(ms / 1000.0).round(1)}s" : "#{ms}ms"
  end

  def format_cost(microdollars)
    return "—" unless microdollars && microdollars > 0
    dollars = microdollars / 1_000_000.0
    if dollars >= 0.01
      "$#{'%.2f' % dollars}"
    else
      "$#{'%.4f' % dollars}"
    end
  end

  def format_tokens(count)
    return "—" unless count && count > 0
    number_with_delimiter(count)
  end

  def pagination_link(path_helper, page, current_page, label: nil, params: {})
    text = label || page.to_s
    if page == current_page
      content_tag(:span, text, class: "page-link current")
    elsif page < 1 || page > (params[:total_pages] || 999)
      content_tag(:span, text, class: "page-link disabled")
    else
      link_to(text, send(path_helper, request.query_parameters.merge(page: page)), class: "page-link")
    end
  end
end
