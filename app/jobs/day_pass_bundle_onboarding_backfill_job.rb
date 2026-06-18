# One-time (re-runnable) backfill: send the onboarding "directions" email to
# people who bought a Day Pass Bundle before the onboarding email existed.
#
# Safe to run repeatedly:
#   - SendProductEmailJob de-dupes per (bundle, "onboarding"), so a holder who
#     already received it won't get a second copy.
#   - It also gates on the onboarding template being enabled, so this is a no-op
#     until the operator turns the template on (configure first, then backfill).
#
# Runs on a worker dyno (full DB access), so the trigger only needs to enqueue
# this job — handy given prod one-off dynos can hit the PG connection ceiling.
class DayPassBundleOnboardingBackfillJob < ApplicationJob
  queue_as :default

  def perform(operator_id: nil)
    ActsAsTenant.without_tenant do
      scope = DayPassBundle.active
      scope = scope.where(operator_id: operator_id) if operator_id

      scope.find_each do |bundle|
        next unless bundle.user_id

        SendProductEmailJob.perform_later(
          "DayPassBundle", bundle.id, bundle.operator_id,
          "day_pass_bundle", "onboarding", bundle.user_id
        )
      end
    end
  end
end
