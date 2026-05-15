module PeopleHelper
  def stage_badge(stage)
    stage = stage.to_s
    label = Operator::PeopleController::STAGE_LABELS[stage] || stage.humanize
    css_class = Operator::PeopleController::STAGE_BADGE_CLASSES[stage] || "badge-secondary"
    content_tag(:span, label, class: "badge #{css_class} ml-2")
  end
end
