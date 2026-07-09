class OfficeVacancyNotificationJob < ApplicationJob
  queue_as :default

  # Runs daily (via a rake task on the external scheduler, like the lease
  # renewal reminder). When an office frees up and people are waiting, it pushes
  # the operator's admins "Office X is available — N waiting. Notify them?",
  # which opens the office queue. Operator-triggered: we alert STAFF and let them
  # work the queue one-by-one; we do NOT auto-blast the waiting members.
  FRESHLY_FREED_WINDOW = 1.day

  def perform
    Operator.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        process_operator(operator)
      end
    rescue => e
      Honeybadger.notify(e)
      Rails.logger.error("OfficeVacancyNotificationJob failed for operator #{operator.id}: #{e.message}")
    end
  end

  private

  def process_operator(operator)
    return unless OfficeWaitlist.for(operator).waiting.any?

    freshly_freed_offices(operator).each do |office|
      SendNotificationsJob.perform_later(office, "OfficeVacancy")
    end
  end

  # Offices whose most recent lease ended within the last day and that have no
  # active lease now. The recency window + daily cadence means each vacancy pages
  # the operator roughly once, without a dedup column. Covers both immediate
  # terminations (end_date set to today) and natural expiry (end_date passes).
  def freshly_freed_offices(operator)
    freed_office_ids = OfficeLease.where(operator: operator)
                                  .where(end_date: FRESHLY_FREED_WINDOW.ago.to_date..Date.current)
                                  .distinct.pluck(:office_id).compact

    Office.where(operator: operator, id: freed_office_ids).visible.select(&:available?)
  end
end
