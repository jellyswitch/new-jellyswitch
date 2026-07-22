class Operator::DayPassBundleSchedulesController < Operator::BaseController
  before_action :require_authentication

  # Admin "Use a pass" — burns one of a member's Day Pass Bundle passes for a
  # chosen day: today = front-desk burn-for-the-member-at-the-desk, a future
  # date = reserve it ahead. Web parity with the mobile admin schedule picker;
  # same interactor, and staff bypass the per-day cap by design (no
  # enforce_daily_limit), matching Api::V1::Admin::MembersController.
  def create
    user = current_tenant.users.friendly.find(params[:user_id])

    unless current_user&.admin_or_manager?(current_location)
      return redirect_back fallback_location: user_admin_day_passes_path(user),
                           alert: "Not authorized to use a pass."
    end

    result = Billing::DayPassBundles::ScheduleDay.call(
      user: user, location: current_location, date: params[:day], performed_by: current_user)

    if result.outcome == :scheduled
      remaining = user.day_pass_bundles.active.where(location: current_location).sum(:passes_remaining)
      day = result.day_pass.day
      # BaseController's set_time_zone makes Time.zone the location's tz here.
      notice = if day == Time.zone.today
                 "Burned a pass for #{user.name} today. #{remaining} left in their pack."
               else
                 "Reserved a pass for #{user.name} on #{day.strftime('%B %-d, %Y')}. #{remaining} left in their pack."
               end
      redirect_back fallback_location: user_admin_day_passes_path(user), notice: notice
    else
      alert = case result.outcome
              when :already_covered then "#{user.name} already has coverage for that day — nothing was burned."
              when :no_bundle then "No active bundle pass covers that day."
              when :invalid_date then "Pick a date between today and #{Billing::DayPassBundles::ScheduleDay::HORIZON_DAYS} days out."
              else "Could not use a pass (#{result.outcome})."
              end
      redirect_back fallback_location: user_admin_day_passes_path(user), alert: alert
    end
  end

  # Admin "Return to pack" — cancels a scheduled (future, bundle-sourced) day
  # and restores the pass to the member's bundle. Today/past days can't be
  # returned here (the burn is the audit record); that's CancelScheduledDay's
  # :too_late guard, same as mobile.
  def destroy
    user = current_tenant.users.friendly.find(params[:user_id])

    unless current_user&.admin_or_manager?(current_location)
      return redirect_back fallback_location: user_admin_day_passes_path(user),
                           alert: "Not authorized to return a pass."
    end

    day_pass = user.day_passes.find(params[:id])
    result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: current_user)

    if result.outcome == :cancelled
      redirect_back fallback_location: user_admin_day_passes_path(user),
                    notice: "Returned the pass to #{user.name}'s pack."
    else
      alert = case result.outcome
              when :too_late then "That day is already today or past — too late to return it."
              when :not_scheduled then "That pass didn't come from a bundle."
              else "Could not return that pass (#{result.outcome})."
              end
      redirect_back fallback_location: user_admin_day_passes_path(user), alert: alert
    end
  end
end
