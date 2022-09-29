
class Operator::SubscriptionsController < Operator::BaseController
  include SubscriptionsHelper
  before_action :background_image

  def index
    authorize Subscription.new
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
      operator: current_tenant
    )

    if result.success?
      flash[:success] = "Welcome to #{current_tenant.name}!"
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

    result = SwitchMembership.call(
      old_subscription: @subscription,
      new_subscription: @new_subscription
    )

    if result.success?
      if admin?
        flash[:success] = "Membership updated."
        turbo_redirect(user_path(@subscription.subscribable))
      else
        flash[:success] = "Your membership has been updated"
        turbo_redirect(home_path)
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
      blob: { text: "#{@subscription.subscribable.name} canceled their membership", type: "post" },
      user: current_tenant.users.admins.first,
      operator: current_tenant,
      notifiable: current_tenant.users.admins
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
end