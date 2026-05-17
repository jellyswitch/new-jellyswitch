module PeopleHelper
  def stage_badge(stage)
    stage = stage.to_s
    label = Operator::PeopleController::STAGE_LABELS[stage] || stage.humanize
    css_class = Operator::PeopleController::STAGE_BADGE_CLASSES[stage] || "badge-secondary"
    content_tag(:span, label, class: "badge #{css_class} ml-2")
  end

  def from_filter_label(from, primary_city:)
    case from
    when "local"  then primary_city || "Local"
    when "out"    then "Out of town"
    when /\Astate:(.+)\z/
      "State: #{Regexp.last_match(1)}"
    else
      "Any"
    end
  end
end
