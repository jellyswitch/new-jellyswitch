require "rails_helper"

RSpec.describe OfficeVacancyNotificationJob, type: :job do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:office)   { create(:office, operator: operator, location: location, name: "Pipkin Suite") }

  # Someone waiting for an office at this operator.
  def add_waiter
    user = create(:user, operator: operator, original_location: location)
    InterestTag.record(user: user, product: "office", source: "concierge")
    user
  end

  # A lease on `office` that already ended `ended_days_ago` days ago (so the
  # office is now available). Bypasses the create-time auto-cull's relevance —
  # the leaseholder here is unrelated to the waiters.
  def end_lease(office, ended_days_ago:)
    create(:office_lease,
           organization: nil,
           user: create(:user, operator: operator, original_location: location),
           operator: operator, location: location, office: office,
           start_date: (ended_days_ago + 60).days.ago.to_date,
           end_date: ended_days_ago.days.ago.to_date)
  end

  it "pushes an OfficeVacancy alert for an office freed within the last day when people wait" do
    add_waiter
    end_lease(office, ended_days_ago: 0)

    expect {
      OfficeVacancyNotificationJob.perform_now
    }.to have_enqueued_job(SendNotificationsJob).with(office, "OfficeVacancy")
  end

  it "does not alert when nobody is waiting" do
    end_lease(office, ended_days_ago: 0)

    expect {
      OfficeVacancyNotificationJob.perform_now
    }.not_to have_enqueued_job(SendNotificationsJob)
  end

  it "does not alert for an office that freed up long ago (outside the window)" do
    add_waiter
    end_lease(office, ended_days_ago: 10)

    expect {
      OfficeVacancyNotificationJob.perform_now
    }.not_to have_enqueued_job(SendNotificationsJob)
  end

  it "does not alert for an office that is still occupied" do
    add_waiter
    create(:office_lease, organization: nil, user: create(:user, operator: operator, original_location: location),
                          operator: operator, location: location, office: office,
                          start_date: 1.month.ago.to_date, end_date: 1.month.from_now.to_date)

    expect {
      OfficeVacancyNotificationJob.perform_now
    }.not_to have_enqueued_job(SendNotificationsJob)
  end
end
