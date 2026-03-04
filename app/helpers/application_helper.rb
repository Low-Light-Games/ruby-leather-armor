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
    when "triage", "sanitize", "classify", "dispatcher", "capability_guardrail", "chronicler" then "type-triage"
    when "intent"                then "type-intent"
    when "mechanical_evaluation" then "type-ruling"
    when "ruling"                then "type-evaluate"
    when "narrate"               then "type-narrate"
    when "dm_query"              then "type-dm-query"
    when "micro_context_update"  then "type-ctx"
    when "macro_narrative_update" then "type-ctx"
    when "edge_pipeline"         then "type-narrate"
    else "type-default"
    end
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
