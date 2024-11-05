class Operator::LandingController < Operator::BaseController
  before_action :background_image
  include LandingHelper
  include EventHelper

  def index
    landing_redirect
  end

  def home
    find_doors
    @member_feedback = MemberFeedback.new
    find_upcoming_events
    @reservation = current_user&.upcoming_or_ongoing_reservation(current_location&.id)
    @announcement = current_tenant.announcements.for_location(current_location).latest
    # for some reason sometimes latest returns activerecord relation
    @announcement = @announcement.first if @announcement.is_a?(ActiveRecord::Relation)
    response.headers["Turbo-Location"] = home_url
    flash.keep
    home_redirect
  end

  def wait
    if !logged_in?
      redirect_to root_path
    end

    if (current_user&.allowed_in?(current_location) && approved?)
      redirect_to home_path
    end
  end

  def activate
    if current_user.out_of_band?
      result = Billing::Subscription::ActivatePendingSubscription.call(
        subscription: current_user.subscriptions.pending.first,
        user: current_user,
        operator: current_tenant,
        start_day: nil,
      )
      if result.success?
        # redirect to home
        flash[:success] = "Welcome!"
        turbo_redirect(home_path, action: restore_if_possible)
      else
        flash[:error] = result.message
        turbo_redirect(activate_path, action: restore_if_possible)
      end
    else
      include_stripe
    end
  end

  def activate_membership
    # update billing info
    token = params[:stripeToken]
    result = Billing::Payment::UpdateUserPayment.call(
      user: current_user,
      token: token,
      out_of_band: false,
    )
    if result.success?
      # activate membership
      result2 = Billing::Subscription::ActivatePendingSubscription.call(
        subscription: current_user.subscriptions.pending.first,
        user: current_user,
        operator: current_tenant,
        start_day: nil,
      )
      if result2.success?
        # redirect to home
        flash[:success] = "Welcome!"
        turbo_redirect(home_path, action: restore_if_possible)
      else
        flash[:error] = result2.message
        turbo_redirect(activate_path, action: restore_if_possible)
      end
    else
      flash[:error] = result.message
      turbo_redirect(activate_path, action: restore_if_possible)
    end
  end

  def choose
    if !logged_in?
      redirect_to root_path
    else
      if (!policy(:payment).enabled? && current_tenant.subdomain != "southlakecoworking") || (current_user.member?(current_location) && approved?) || admin?
        redirect_to home_path
      end
    end
    flash.keep
    @day_pass_types = current_location.day_pass_types.available.visible
    @plans = current_location.plans.for_individuals.order("amount_in_cents DESC")
    @plan = current_location.plans.available.visible.individual.cheapest
    @rooms = current_location.rooms.visible.rentable

    @available_rooms_now = @rooms.available
  end

  def upgrade
    @day_pass_types = current_location.day_pass_types.available.visible.order("amount_in_cents DESC")
    @plans = current_location.plans.for_individuals.order("amount_in_cents DESC")
  end

  # High level pages for nav
  def members_groups
    authorize :member_group, :show?
    @report = Jellyswitch::Report.new(current_tenant, current_location)
  end

  def plans_day_passes
    authorize :plan, :index?
  end

  def customization
    authorize :dashboard, :show?
  end

  def announcements_events
    authorize :dashboard, :show?
  end

  def privacy_policy
  end

  private

  def find_doors
    @doors = Door.all
    @doors = @doors.reject { |door| door.private? } unless admin?
  end
end
