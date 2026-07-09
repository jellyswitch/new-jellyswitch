# The office "waitlist" (ADR 0022): there is no separate waitlist model — it is
# simply everyone carrying an `office` InterestTag, presented as a FAIRNESS
# QUEUE. Ordering:
#   1. current customers first (active member / day-passer) by earliest signup
#      (tenure / loyalty), then
#   2. outside parties in the order they expressed interest (tag created_at).
#
# The operator works the queue one person at a time (see OfficeOutreach). People
# who have since signed an office lease are `leased` and drop out of the working
# set (their tag is also culled on lease — see OfficeLease auto-cull).
class OfficeWaitlist
  Entry = Struct.new(:user, :tag, :status, :customer, keyword_init: true) do
    def customer? = customer
    def resolved? = status == :leased
    def waiting_since = tag.created_at
    def waiting_days = ((Time.current - tag.created_at) / 1.day).floor
    def source = tag.source
  end

  def self.for(operator)
    new(operator: operator)
  end

  def initialize(operator:)
    @operator = operator
  end

  # All office-tagged people, ordered. Includes `leased` people (marked as such);
  # use #waiting for the working queue.
  def entries
    @entries ||= build_entries
  end

  # The working queue — everyone still waiting for an office (not yet leased).
  def waiting
    entries.reject(&:resolved?)
  end

  # The demand-vs-vacancy stat: how many are waiting, the longest wait, and a
  # rough monthly-revenue figure (waiting head-count x average current office
  # rent). Compare against Office.available_for_lease (usually empty).
  def demand
    w = waiting
    {
      waiting_count: w.size,
      oldest_days: w.map(&:waiting_days).max || 0,
      monthly_cents: w.size * average_office_monthly_cents,
    }
  end

  private

  attr_reader :operator

  def build_entries
    tags = InterestTag.where(operator: operator).for_product("office").includes(:user).to_a
    tags.reject! { |t| t.user.nil? }
    last_outreach = latest_outreach_by_user(tags.map(&:user_id))

    rows = tags.map do |tag|
      user = tag.user
      status = OfficeOutreach.status_for(user, latest_outreach_kind: last_outreach.fetch(user.id, nil))
      Entry.new(user: user, tag: tag, status: status, customer: customer?(user))
    end

    customers, outside = rows.partition(&:customer?)
    customers.sort_by! { |e| [e.user.created_at, e.user.id] }  # tenure — earliest signup first
    outside.sort_by!   { |e| [e.tag.created_at, e.tag.id] }    # interest date — earliest first
    customers + outside
  end

  # A "current customer" for tenure ordering: an active member or day-passer.
  # (No virtual-office product exists in the schema; office leaseholders are
  # culled off the list, so they don't reach here.)
  def customer?(user)
    user.has_active_subscription? || user.has_active_day_pass?
  end

  # user_id => most recent outreach kind (office_offered / office_declined),
  # loaded in one query. Ordered ascending so the last write wins per user.
  def latest_outreach_by_user(user_ids)
    return {} if user_ids.empty?

    Activity.where(user_id: user_ids, kind: OfficeOutreach::OUTREACH_KINDS)
            .order(:occurred_at, :id)
            .pluck(:user_id, :kind)
            .each_with_object({}) { |(uid, kind), acc| acc[uid] = kind }
  end

  def average_office_monthly_cents
    @average_office_monthly_cents ||= begin
      prices = OfficeLease.active.where(operator: operator)
                          .includes(subscription: :plan)
                          .filter_map { |lease| lease.subscription&.plan&.amount_in_cents }
      prices.empty? ? 0 : (prices.sum / prices.size)
    end
  end
end
