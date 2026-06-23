require "rails_helper"

RSpec.describe Billing::Leasing::UpdateEndDate do
  # "Terminate Lease (now)" runs this. It used to read the lease end date
  # straight off subscription.ended_at and hard-fail when that was nil — which
  # is exactly the case for a "zombie" lease whose subscription was already
  # cancelled (e.g. the member self-cancelled/downgraded). That left admins
  # unable to end the lease at all. It must fall back to today instead.
  let(:office_lease) { create(:office_lease, start_date: Date.today - 1.month, end_date: Date.today + 6.months) }

  it "ends the lease on the subscription's ended_at when present" do
    allow(office_lease.subscription).to receive(:ended_at).and_return(Date.today - 3.days)

    result = described_class.call(office_lease: office_lease)

    expect(result).to be_success
    expect(office_lease.reload.end_date).to eq(Date.today - 3.days)
  end

  it "falls back to today when the subscription has no ended_at, instead of failing" do
    allow(office_lease.subscription).to receive(:ended_at).and_return(nil)

    result = described_class.call(office_lease: office_lease)

    expect(result).to be_success
    expect(office_lease.reload.end_date).to eq(Date.current)
  end
end
