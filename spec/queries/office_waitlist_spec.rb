require "rails_helper"

RSpec.describe OfficeWaitlist do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  # A person carrying an office interest tag. `created_at` is their signup
  # (tenure); `tag_at` is when they expressed office interest.
  def office_person(created_at:, source: "concierge", tag_at: nil)
    user = create(:user, operator: operator, original_location: location, created_at: created_at)
    tag = InterestTag.record(user: user, product: "office", source: source)
    tag.update_column(:created_at, tag_at) if tag_at
    user
  end

  def make_member(user)
    plan = create(:plan, operator: operator, amount_in_cents: 20_500)
    create(:subscription, plan: plan, subscribable: user, billable: user, active: true)
  end

  it "lists only office-interest people for the operator" do
    wanted = office_person(created_at: 1.year.ago)
    other = create(:user, operator: operator, original_location: location)
    InterestTag.record(user: other, product: "day_pass", source: "last_purchase")

    expect(OfficeWaitlist.for(operator).entries.map(&:user)).to eq([wanted])
  end

  describe "ordering (the fairness queue)" do
    it "puts current customers first by tenure, then outside parties by interest date" do
      outside_early = office_person(created_at: 2.months.ago, tag_at: 6.months.ago)
      outside_late  = office_person(created_at: 1.month.ago, tag_at: 1.month.ago)

      cust_old = office_person(created_at: 3.years.ago, source: "staff")
      make_member(cust_old)
      cust_new = office_person(created_at: 6.months.ago)
      make_member(cust_new)

      order = OfficeWaitlist.for(operator).entries.map(&:user)
      expect(order).to eq([cust_old, cust_new, outside_early, outside_late])
    end

    it "treats a current day-passer as a customer" do
      day_passer = office_person(created_at: 5.years.ago)
      create(:day_pass, user: day_passer, operator: operator, location: location, day: Date.current)
      outsider = office_person(created_at: 1.day.ago, tag_at: 1.day.ago)

      entries = OfficeWaitlist.for(operator).entries
      expect(entries.map(&:user)).to eq([day_passer, outsider])
      expect(entries.first).to be_customer
      expect(entries.last).not_to be_customer
    end
  end

  describe "per-entry status" do
    it "carries the derived outreach status and the interest source" do
      person = office_person(created_at: 1.year.ago, source: "concierge")
      office = create(:office, operator: operator, location: location)
      OfficeOutreach.offer!(user: person, office: office)

      entry = OfficeWaitlist.for(operator).entries.first
      expect(entry.status).to eq(:offered)
      expect(entry.source).to eq("concierge")
      expect(entry.waiting_days).to be >= 0
    end
  end

  describe "#demand" do
    it "counts waiting people, the longest wait, and rough monthly demand" do
      office_person(created_at: 1.year.ago, tag_at: 100.days.ago)
      office_person(created_at: 1.year.ago, tag_at: 10.days.ago)

      # an active office lease at $500/mo anchors the average-rent estimate
      plan = create(:plan, operator: operator, amount_in_cents: 50_000)
      sub = create(:subscription, plan: plan)
      create(:office_lease, organization: nil, user: create(:user, operator: operator, original_location: location),
                            operator: operator, location: location,
                            office: create(:office, operator: operator, location: location), subscription: sub)

      demand = OfficeWaitlist.for(operator).demand
      expect(demand[:waiting_count]).to eq(2)
      expect(demand[:oldest_days]).to eq(100)
      expect(demand[:monthly_cents]).to eq(2 * 50_000)
    end

    it "excludes leased people from the working queue and marks them leased" do
      still_waiting = office_person(created_at: 1.year.ago)

      # Someone who holds an office lease but still carries an office tag — the
      # tag is recorded AFTER the lease so the create-time auto-cull doesn't
      # remove it, exercising the derived-`leased` safety net directly.
      leased = create(:user, operator: operator, original_location: location)
      create(:office_lease, organization: nil, user: leased, operator: operator, location: location,
                            office: create(:office, operator: operator, location: location))
      InterestTag.record(user: leased, product: "office", source: "staff")

      waitlist = OfficeWaitlist.for(operator)
      expect(waitlist.waiting.map(&:user)).to eq([still_waiting])
      expect(waitlist.demand[:waiting_count]).to eq(1)
      expect(waitlist.entries.find { |e| e.user == leased }.status).to eq(:leased)
    end
  end
end
