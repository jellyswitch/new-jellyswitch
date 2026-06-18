require "rails_helper"

RSpec.describe DayPassBundleOnboardingBackfillJob, type: :job do
  let(:operator)  { create(:operator) }
  let(:location)  { create(:location, operator: operator) }
  let(:user)      { create(:user, operator: operator, current_location: location) }
  let(:pack_type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }

  def bundle_with(passes)
    create(:day_pass_bundle, user: user, day_pass_type: pack_type, operator: operator,
                             location: location, quantity_purchased: 5, passes_remaining: passes)
  end

  it "enqueues an onboarding send for each active (passes-remaining) bundle holder" do
    active = bundle_with(3)
    expect {
      described_class.perform_now
    }.to have_enqueued_job(SendProductEmailJob)
      .with("DayPassBundle", active.id, operator.id, "day_pass_bundle", "onboarding", user.id)
  end

  it "skips fully-used (inactive) bundles" do
    empty = bundle_with(0)
    expect {
      described_class.perform_now
    }.not_to have_enqueued_job(SendProductEmailJob)
      .with("DayPassBundle", empty.id, anything, anything, anything, anything)
  end

  it "can be scoped to a single operator" do
    other_op  = create(:operator)
    other_loc = create(:location, operator: other_op)
    other_usr = create(:user, operator: other_op, current_location: other_loc)
    other_pk  = create(:day_pass_type, operator: other_op, location: other_loc, quantity: 5)
    other_bundle = create(:day_pass_bundle, user: other_usr, day_pass_type: other_pk,
                          operator: other_op, location: other_loc, passes_remaining: 4)
    mine = bundle_with(2)

    expect {
      described_class.perform_now(operator_id: operator.id)
    }.to have_enqueued_job(SendProductEmailJob).with("DayPassBundle", mine.id, operator.id, anything, anything, anything)

    expect(SendProductEmailJob).not_to have_been_enqueued
      .with("DayPassBundle", other_bundle.id, anything, anything, anything, anything)
  end
end
