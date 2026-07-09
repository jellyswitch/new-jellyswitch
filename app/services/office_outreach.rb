# Per-person outreach on the office fairness queue (ADR 0022).
#
# The office waitlist is worked ONE-BY-ONE: the operator offers a freed office to
# the longest-waiting eligible person, waits for a yes/no, then moves on. That
# needs a per-person status — not_contacted -> offered -> declined -> leased.
#
# We do NOT store status in a new column. Offers and declines are logged as
# Activities (kinds office_offered / office_declined) so they land on the
# person's existing CRM timeline and give the offered -> declined -> leased
# attribution for free. `leased` is derived from the person holding an office
# lease. Status is read back from those signals.
module OfficeOutreach
  OFFER_KIND = "office_offered".freeze
  DECLINE_KIND = "office_declined".freeze
  OUTREACH_KINDS = [OFFER_KIND, DECLINE_KIND].freeze

  STATUSES = %i[not_contacted offered declined leased].freeze

  # Sentinel so callers can pass a preloaded latest-outreach kind (including nil)
  # to avoid an N+1 when deriving status for a whole queue.
  UNSET = Object.new.freeze

  # Record that the operator offered a (freed) office to this person. `office`
  # is optional context — the operator may reach out before a specific vacancy.
  def self.offer!(user:, office: nil, added_by: nil)
    log(user: user, office: office, kind: OFFER_KIND, added_by: added_by)
  end

  # Record that the person declined an offer. `office` is optional context.
  def self.decline!(user:, office: nil, added_by: nil)
    log(user: user, office: office, kind: DECLINE_KIND, added_by: added_by)
  end

  # not_contacted -> offered -> declined -> leased.
  # leased wins over everything (they got an office); otherwise the most recent
  # outreach Activity decides offered vs declined.
  def self.status_for(user, latest_outreach_kind: UNSET)
    return :leased if user.has_active_lease?

    kind = latest_outreach_kind.equal?(UNSET) ? latest_outreach_kind_for(user) : latest_outreach_kind
    case kind
    when DECLINE_KIND then :declined
    when OFFER_KIND then :offered
    else :not_contacted
    end
  end

  def self.latest_outreach_kind_for(user)
    user.activities.where(kind: OUTREACH_KINDS).order(:occurred_at, :id).last&.kind
  end

  def self.log(user:, office:, kind:, added_by:)
    Activity.log(
      user: user,
      operator: office&.operator || user.operator,
      kind: kind,
      subject: office,
      occurred_at: Time.current,
      payload: {
        "office_id" => office&.id,
        "office_name" => office&.name,
        "added_by_id" => added_by&.id,
      }.compact,
    )
  end
  private_class_method :log
end
