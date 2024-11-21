
class Operator::SubscriptionsController < Operator::BaseController
  include SubscriptionsHelper
  before_action :background_image

  def index
    authorize Subscription.new
    if params[:plan_category_id].present?
      @plan_category = current_location.plan_categories.find(params[:plan_category_id])
      if @plan_category.present?
        @plans = @plan_category.plans.visible.available.for_location(current_location).order(:amount_in_cents)
      else
        default_plans
      end
    else
      default_plans
    end
  end

  def new
    @subscription = Subscription.new
    authorize @subscription
    find_plan
    include_stripe
  end

  def create
    authorize Subscription, :new?

    @subscription = new_subscription
    start_day = compute_start_day

    out_of_band = params[:out_of_band] || @subscription.subscribable.out_of_band
    token = params[:stripeToken]
    card_added = @subscription.subscribable.card_added?

    interactor = Billing::Subscription::UpdatePaymentAndCreateSubscription

    if card_added
      interactor = Billing::Subscription::CreateSubscription
    end

    result = interactor.call(
      subscription: @subscription,
      token: token,
      user: @subscription.subscribable,
      start_day: start_day,
      out_of_band: out_of_band,
      operator: current_tenant,
      location: current_location
    )

    if result.success?
      flash[:success] = "Welcome to #{current_location.name}!"
      session[:should_track_pixels] = true
      turbo_redirect(root_path)
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root)
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def edit
    find_subscription
    authorize @subscription
    background_image
  end

  def update
    find_subscription
    authorize @subscription
    @new_subscription = new_subscription

    result = UpdateMembership.call(
      old_subscription: @subscription,
      new_subscription: @new_subscription,
      blob: { text: "#{@subscription.subscribable.name} switched their membership from #{@subscription.plan.name}, to #{@new_subscription.plan.name} ", type: "membership_updated" },
      user: current_location.users.admins.first,
      operator: current_tenant,
      location: current_location,
      notifiable: current_location.users.admins
    )

    if result.success?
      if admin?
        flash[:success] = "Membership updated."
        turbo_redirect(user_path(@subscription.subscribable))
      else
        flash[:success] = "Your membership has been updated"
        turbo_redirect(user_memberships_path(current_user))
      end
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root)
    end
  end

  def destroy
    find_subscription
    authorize @subscription

    result = SetSubscriptionForCancellation.call(
      subscription: @subscription,
      blob: { text: "#{@subscription.subscribable.name} cancelled their membership.", type: "membership_cancellation" },
      user: current_location.users.admins.first,
      operator: current_tenant,
      location: current_location,
      notifiable: current_location.users.admins
    )

    if result.success?
      flash[:success] = "Membership scheduled for cancellation."
      turbo_redirect(referrer_or_root)
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root)
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def destroy_subscription_now
    find_subscription
    authorize @subscription


    result = Billing::Subscription::CancelSubscriptionNow.call(
      subscription: @subscription,
      blob: { text: "#{@subscription.subscribable.name} cancelled their membership.", type: "membership_cancellation" },
      user: current_location.users.admins.first,
      operator: current_tenant,
      location: current_location,
      notifiable: current_location.users.admins,
      creditable: @subscription.subscribable
    )

    if result.success?
      flash[:success] = "Membership cancelled."
      turbo_redirect(referrer_or_root)
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root)
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan_id)
  end

  def new_subscription
    subscription = Subscription.new(subscription_params)
    subscription.subscribable = current_user
    subscription.active = true
    subscription
  end

  def find_plan(key=:plan_id)
    @plan = current_location.plans.find(params[key])
  end

  def default_plans
    @plans = current_location.plans.uncategorized.individual.visible.available.order(:amount_in_cents)
  end
end