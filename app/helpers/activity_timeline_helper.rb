module ActivityTimelineHelper
  ICONS = {
    "signup"              => "fas fa-user-plus text-info",
    "tour"                => "fas fa-walking text-info",
    "checkin"             => "fas fa-sign-in-alt text-secondary",
    "door_punch"          => "fas fa-door-open text-secondary",
    "reservation"         => "fas fa-calendar-check text-primary",
    "day_pass"            => "fas fa-ticket-alt text-primary",
    "subscription_started"=> "fas fa-users text-success",
    "subscription_ended"  => "fas fa-user-slash text-warning",
    "payment_succeeded"   => "fas fa-dollar-sign text-success",
    "payment_failed"      => "fas fa-dollar-sign text-danger",
    "note"                => "fas fa-sticky-note text-muted",
    "email_sent"          => "fas fa-envelope text-muted",
    "email_opened"        => "fas fa-envelope-open text-info",
    "email_clicked"       => "fas fa-mouse-pointer text-info",
    "email_replied"       => "fas fa-reply text-info",
  }.freeze

  def activity_icon_class(activity)
    ICONS[activity.kind] || "fas fa-circle text-muted"
  end

  # Returns a short, human-readable label for one Activity row. Uses the
  # denormalized payload — never queries the subject. Falls back to the kind
  # name if payload is empty (e.g. very old rows or backfill misses).
  def activity_label(activity)
    p = activity.payload || {}

    case activity.kind
    when "signup"               then "Signed up"
    when "tour"                 then p["notes"].present? ? "Tour logged — #{truncate(p['notes'], length: 60)}" : "Tour logged"
    when "checkin"              then "Checked in at #{p['location_name'] || 'space'}"
    when "door_punch"           then "Entered #{p['door_name'] || 'a door'}"
    when "reservation"          then "Booked #{p['room_name'] || 'a room'}"
    when "day_pass"             then p["complimentary"] ? "Comped a day pass" : "Bought a day pass"
    when "subscription_started" then "Started membership: #{p['plan_name'] || 'plan'}"
    when "subscription_ended"   then "Ended membership: #{p['plan_name'] || 'plan'}"
    when "payment_succeeded"    then "Paid #{ActiveSupport::NumberHelper.number_to_currency((p['amount_paid'] || 0) / 100.0)}"
    when "payment_failed"       then "Payment failed (#{p['number'] || 'invoice'})"
    when "note"                 then "Note from #{p['author_name'] || 'staff'}: #{p['content_preview'] || ''}"
    when "email_sent"           then "Sent: #{p['subject'] || '(no subject)'}"
    when "email_opened"         then "Opened: #{p['subject'] || '(no subject)'}"
    when "email_clicked"        then "Clicked: #{p['subject'] || '(no subject)'}"
    when "email_replied"        then "Replied to: #{p['subject'] || '(no subject)'}"
    else activity.kind.humanize
    end
  end

  TABS = [
    { key: "recent",       label: "Recent" },
    { key: "emails",       label: "Emails" },
    { key: "tours",        label: "Tours" },
    { key: "reservations", label: "Reservations" },
    { key: "payments",     label: "Payments" },
    { key: "notes",        label: "Notes" },
  ].freeze

  KIND_GROUPS = {
    "emails"       => %w[email_sent email_opened email_clicked email_replied],
    "tours"        => %w[tour],
    "reservations" => %w[reservation],
    "payments"     => %w[payment_succeeded payment_failed],
    "notes"        => %w[note],
  }.freeze

  def activity_timeline_pretty_time(activity)
    activity.occurred_at.strftime("%b %-d, %Y · %-l:%M%P")
  end
end
