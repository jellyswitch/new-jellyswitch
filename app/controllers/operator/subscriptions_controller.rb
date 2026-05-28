
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

  # GET /subscriptions/:id has no dedicated show page — subscription details
  # live on the user's change-account / membership overview. We declare a
  # show action anyway because `resources :subscriptions` registers the
  # route, and without a matching action Rails raises ActionNotFound → 404.
  # That bit a real member who long-pressed the "Cancel Membership" link
  # in the mobile WKWebView wrapper: iOS previews the raw GET href, not
  # the DELETE that data-turbo-method would actually fire, so the preview
  # rendered the Rails 404 page mid-cancellation and made the user think
  # the flow was broken.
  def show
    find_subscription
    authorize @subscription, :edit?
    redirect_to user_change_account_path(@subscription.subscribable)
  end

  def create
    authorize Subscription, :new?

    @subscription = new_subscription
    start_day = compute_start_day

    out_of_band = params[:out_of_band] || @subscription.subscribable.out_of_band
    token = params[:stripeToken]
    card_added = @subscription.subscribable.card_added_for_location?(current_location)

    interactor = Billing::Subscription::UpdatePaymentAndCreateSubscription

    if card_added
      interactor = Billing::Subscription::CreateSubscription
    end

    # Validate discount code if provided
    discount_code = nil
    if params[:discount_code].present?
      validate_result = Billing::DiscountCodes::ValidateCode.call(
        code: params[:discount_code],
        location: current_location,
        product_type: "membership"
      )
      if validate_result.success?
        discount_code = validate_result.discount_code
      else
        flash[:error] = validate_result.message
        turbo_redirect(referrer_or_root)
        return
      end
    end

    result = interactor.call(
      subscription: @subscription,
      token: token,
      user: @subscription.subscribable,
      start_day: start_day,
      out_of_band: out_of_band,
      operator: current_tenant,
      location: current_location,
      discount_code: discount_code
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

    # Pre-flight: SwitchMembership eventually calls
    # Stripe::Subscription.update on the old sub, which raises
    # Stripe::InvalidRequestError ("Cannot update a subscription whose
    # status is paused") for paused rows — and the exception bubbles up
    # as a 500 / Whoops flash. Return an actionable message instead.
    if @subscription.paused?
      flash[:error] = "Your membership is paused. Please unpause it first to switch plans."
      turbo_redirect(user_memberships_path(current_user))
      return
    end

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

    plan = @subscription.plan
    result = SetSubscriptionForCancellation.call(
      subscription: @subscription,
      blob: { text: "canceled their #{plan.name} membership (#{plan.pretty_amount}/#{plan.interval}).", type: "membership_cancellation" },
      user: @subscription.subscribable,
      operator: current_tenant,
      location: current_location,
      notifiable: current_location.users.admins
    )

    if result.success?
      flash[:success] = "Membership scheduled for cancellation."
      turbo_redirect(post_cancel_choices_path)
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


    plan = @subscription.plan
    result = Billing::Subscription::CancelSubscriptionNow.call(
      subscription: @subscription,
      blob: { text: "canceled their #{plan.name} membership (#{plan.pretty_amount}/#{plan.interval}).", type: "membership_cancellation" },
      user: @subscription.subscribable,
      operator: current_tenant,
      location: current_location,
      notifiable: current_location.users.admins,
      creditable: @subscription.subscribable
    )

    if result.success?
      flash[:success] = "Membership cancelled."
      turbo_redirect(post_cancel_choices_path)
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

  # After a successful cancel, land the member on the membership choices
  # page so they can immediately pick a different plan (or leave). The
  # prior `referrer_or_root` redirect dropped them back on the membership
  # detail page they came from, which now showed an "X scheduled to cancel"
  # status with no path forward except hunting through nav.
  #
  # Operators that use plan categories get the categories landing page;
  # otherwise the flat plan-list at /subscriptions does the job.
  def post_cancel_choices_path
    if current_location&.has_categories?
      plan_categories_path
    else
      subscriptions_path
    end
  end

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