module ActivityTimelineHelper
  ICONS = {
    "signup"              => "fas fa-user-plus text-info",
    "tour"                => "fas fa-walking text-info",
    "tour_request"        => "fas fa-walking text-info",
    "chat"                => "fas fa-comments text-info",
    "checkin"             => "fas fa-sign-in-alt text-secondary",
    "door_punch"          => "fas fa-door-open text-secondary",
    "reservation"         => "fas fa-calendar-check text-primary",
    "day_pass"            => "fas fa-ticket-alt text-primary",
    "day_pass_bundle"     => "fas fa-layer-group text-primary",
    "subscription_started"=> "fas fa-users text-success",
    "subscription_ended"  => "fas fa-user-slash text-warning",
    "office_lease"        => "fas fa-building text-success",
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
    when "tour_request"         then tour_request_label(p)
    when "chat"                 then p["intent"].present? ? "Chatted with the Concierge — #{p['intent'].humanize.downcase}" : "Chatted with the Concierge"
    when "checkin"              then "Checked in at #{p['location_name'] || 'space'}"
    when "door_punch"           then "Entered #{p['door_name'] || 'a door'}"
    when "reservation"          then "Booked #{p['room_name'] || 'a room'}"
    when "day_pass"             then p["complimentary"] ? "Comped a day pass" : "Bought a day pass"
    when "day_pass_bundle"      then p["quantity"].to_i > 0 ? "Bought a #{p['quantity']}-pack day pass bundle" : "Bought a day pass bundle"
    when "subscription_started" then "Started membership: #{p['plan_name'] || 'plan'}"
    when "subscription_ended"   then "Ended membership: #{p['plan_name'] || 'plan'}"
    when "office_lease"         then "Leased office: #{p['office_name'] || 'office'}"
    when "payment_succeeded"    then "Paid #{ActiveSupport::NumberHelper.number_to_currency(payment_amount_cents(p) / 100.0)}"
    when "payment_failed"       then "Payment failed (#{p['number'] || 'invoice'})"
    when "note"
      if p["owner_reassigned"]
        "Owner reassigned from #{p['previous_owner_name'] || 'no one'} to #{p['new_owner_name'] || 'no one'} by #{p['actor_name'] || 'staff'}"
      else
        "Note from #{p['author_name'] || 'staff'}: #{p['content_preview'] || ''}"
      end
    when "email_sent"           then "Sent: #{p['subject'] || '(no subject)'}"
    when "email_opened"         then "Opened email"
    when "email_clicked"        then "Clicked: #{engagement_subject(activity, p)}"
    when "email_replied"        then "Replied to: #{engagement_subject(activity, p)}"
    else activity.kind.humanize
    end
  end

  # The widget request row carries what the prospect actually typed — staff
  # shouldn't have to open the alert email to read it.
  def tour_request_label(p)
    parts = ["Tour request"]
    parts << "“#{truncate(p['message'], length: 60)}”" if p["message"].present?
    parts << "(prefers #{truncate(p['preferred_time'], length: 40)})" if p["preferred_time"].present?
    parts.join(" — ")
  end

  # Invoice#amount_paid lags amount_due for invoices whose status is "paid"
  # but didn't come through Stripe's invoice.payment_succeeded webhook
  # (e.g. direct PaymentIntent captures for day pass / room reservations).
  # Christine Crook's $40 day pass surfaced this — the activity payload
  # stored amount_paid=0 even though status="paid" and amount_due=4000.
  # Fall back to amount_due so the timeline displays the real amount.
  def payment_amount_cents(payload)
    paid = payload["amount_paid"].to_i
    return paid if paid > 0
    payload["amount_due"].to_i
  end

  # Windowed last-touch attribution for a conversion row: the campaign the Person
  # opened within 14 days before this conversion, if any. Only resolves for
  # conversion kinds, and loads the Person's opened sends ONCE per render (memoized)
  # so a timeline of many conversion rows doesn't fire a query per row.
  def attributed_campaign(activity)
    return nil unless Campaigns::AttributionReport::CONVERSION_KINDS.include?(activity.kind)
    Campaigns::AttributionReport.campaign_for_conversion(activity, opened_sends: opened_sends_for(activity.user_id))
  end

  def opened_sends_for(user_id)
    @opened_sends_cache ||= {}
    @opened_sends_cache[user_id] ||= CampaignSend.where(user_id: user_id, opened: true)
                                                 .where.not(opened_at: nil)
                                                 .includes(:campaign)
                                                 .order(opened_at: :desc)
                                                 .to_a
  end

  # Sendgrid's open/click webhook events don't carry the email subject,
  # so engagement activities are logged without one. Fall back to the most
  # recent email_sent subject for the same user in the prior 60 days —
  # in practice the matching send always lands seconds before the open.
  def engagement_subject(activity, payload)
    return payload["subject"] if payload["subject"].present?

    prior_subject = Activity
      .where(user_id: activity.user_id, kind: "email_sent")
      .where(occurred_at: (activity.occurred_at - 60.days)..activity.occurred_at)
      .order(occurred_at: :desc)
      .limit(1)
      .pluck(Arel.sql("payload->>'subject'"))
      .first

    prior_subject.presence || "(no subject)"
  end

  TABS = [
    { key: "recent",       label: "Recent" },
    { key: "emails",       label: "Emails" },
    { key: "tours",        label: "Tours" },
    { key: "reservations", label: "Reservations" },
    { key: "payments",     label: "Payments" },
    { key: "notes",        label: "Notes" },
    { key: "doors",        label: "Doors" },
  ].freeze

  KIND_GROUPS = {
    "emails"       => %w[email_sent email_opened email_clicked email_replied],
    "tours"        => %w[tour tour_request],
    "reservations" => %w[reservation],
    "payments"     => %w[payment_succeeded payment_failed],
    "notes"        => %w[note],
    "doors"        => %w[door_punch],
  }.freeze

  def activity_timeline_pretty_time(activity)
    activity.occurred_at.strftime("%b %-d, %Y · %-l:%M%P")
  end

  # The secondary line under a timeline card.
  #
  # For most kinds that is `occurred_at` — when the thing happened. Reservations
  # are the exception: `occurred_at` is when the member clicked "book", which
  # tells staff nothing about when the room was actually held, so those cards
  # show the booked window and its duration instead. Day-pass and bundle cards
  # roll up the room time booked against them, which is what `hours` carries —
  # pass a TimelineHoursIndex built for the whole page (see TimelineHoursIndex).
  def activity_timeline_subtitle(activity, hours: nil)
    subtitle =
      case activity.kind
      when "reservation"     then reservation_subtitle(activity)
      when "day_pass"        then day_pass_subtitle(activity, hours)
      when "day_pass_bundle" then day_pass_bundle_subtitle(activity, hours)
      end

    subtitle.presence || activity_timeline_pretty_time(activity)
  end

  # "Aug 18, 2026 · 2pm–3:30pm · 1h 30m". Reads the denormalized payload, which
  # Reservation keeps in step on edit, early-end, and cancel.
  def reservation_subtitle(activity)
    p = activity.payload || {}
    starts_at = parse_payload_time(p["datetime_in"])
    return nil if starts_at.nil?

    minutes = p["minutes"].to_i
    parts = [
      "#{starts_at.strftime('%b %-d, %Y')} · " \
      "#{pretty_clock(starts_at)}–#{pretty_clock(starts_at + minutes.minutes)} · " \
      "#{pretty_duration(minutes)}",
    ]
    parts << "cancelled" if p["cancelled"]
    parts.join(" · ")
  end

  def day_pass_subtitle(activity, hours)
    day = parse_payload_date(activity.payload&.dig("day"))
    return nil if day.nil?

    "#{day.strftime('%b %-d, %Y')} · #{pretty_booked(hours&.minutes_on(day).to_i)}"
  end

  def day_pass_bundle_subtitle(activity, hours)
    return nil if activity.subject_id.nil?

    summary = hours&.bundle(activity.subject_id)
    return nil if summary.nil? || summary[:quantity].to_i.zero?

    "#{activity.occurred_at.strftime('%b %-d, %Y')} · " \
      "#{summary[:used]} of #{summary[:quantity]} used · #{pretty_booked(summary[:minutes].to_i)}"
  end

  def pretty_booked(minutes)
    minutes.positive? ? "#{pretty_duration(minutes)} booked" : "no room time booked"
  end

  def pretty_duration(minutes)
    hours, remainder = minutes.to_i.divmod(60)
    return "#{remainder}m" if hours.zero?
    return "#{hours}h" if remainder.zero?
    "#{hours}h #{remainder}m"
  end

  # Drops the ":00" on the hour so a window reads "2pm–3:30pm", not "2:00pm–3:30pm".
  def pretty_clock(time)
    time.min.zero? ? time.strftime("%-l%P") : time.strftime("%-l:%M%P")
  end

  # Time.parse, not Time.zone.parse: the payload stores the room's local time
  # with its offset, and Time.zone.parse would re-render it in the app zone
  # (UTC on Heroku), shifting every displayed window.
  def parse_payload_time(value)
    value.present? ? Time.parse(value.to_s) : nil
  rescue ArgumentError, TypeError
    nil
  end

  def parse_payload_date(value)
    value.present? ? Date.parse(value.to_s) : nil
  rescue ArgumentError, TypeError
    nil
  end
end
