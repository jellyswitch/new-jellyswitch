class Api::V1::Admin::MembersController < Api::V1::Admin::BaseController
  def index
    users = current_tenant.users
                          .where(approved: true, archived: false)
                          .where.not(role: 'admin')
                          .order(:name)

    users = search_users(users) if params[:q].present?
    users = users.offset(params[:offset].to_i).limit(30)

    render json: users.map { |u| member_list_json(u) }
  end

  def unapproved
    users = current_tenant.users
                          .where(approved: false, archived: false)
                          .where.not(role: 'admin')
                          .order(created_at: :desc)

    users = search_users(users) if params[:q].present?
    users = users.offset(params[:offset].to_i).limit(30)

    render json: users.map { |u| member_list_json(u) }
  end

  def archived
    users = current_tenant.users
                          .where(archived: true)
                          .where.not(role: 'admin')
                          .order(:name)

    users = search_users(users) if params[:q].present?
    users = users.offset(params[:offset].to_i).limit(30)

    render json: users.map { |u| member_list_json(u) }
  end

  def show
    user = current_tenant.users.find(params[:id])
    active_sub = user.subscriptions.find { |s| s.active? && !s.pending? }
    last_checkin = user.checkins.order(datetime_in: :desc).first

    render json: {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      bio: user.bio,
      linkedin: user.try(:linkedin),
      twitter: user.try(:twitter),
      website: user.try(:website),
      role: user.role,
      approved: user.approved,
      plan_name: active_sub&.plan&.name,
      credit_balance: user.credit_balance,
      has_profile_photo: user.has_profile_photo?,
      ltv: Invoice.where(billable: user, operator: current_tenant).sum("GREATEST(amount_paid, amount_due)"),
      last_checkin: last_checkin&.datetime_in,
      member_since: user.created_at,
      payment_method: user.try(:payment_method) || 'None',
      day_pass_count: user.day_passes.where(operator: current_tenant).count,
      reservation_count: user.reservations.where(cancelled: false).count,
      invoice_count: Invoice.where(billable: user, operator: current_tenant).count,
      organization_name: user.try(:organization)&.try(:name),
      day_passes: user.day_passes.where(operator: current_tenant).order(day: :desc).limit(10).map { |dp|
        { id: dp.id, date: dp.day&.strftime("%B %e, %Y"), type_name: dp.day_pass_type&.name }
      },
      marketing_suppressed: user.marketing_suppressed,
      marketing_suppressed_reason: user.marketing_suppressed_reason,
      inactive_dismissed_at: user.inactive_dismissed_at&.iso8601,
      point_of_contact_id: user.point_of_contact_id,
      point_of_contact_name: user.point_of_contact&.name,
    }
  end

  def suppress
    user = current_tenant.users.find(params[:id])
    reason = params[:reason].presence || "Suppressed by admin"
    user.update!(marketing_suppressed: true, marketing_suppressed_reason: reason)
    render json: { success: true, marketing_suppressed: true }
  end

  def unsuppress
    user = current_tenant.users.find(params[:id])
    user.update!(marketing_suppressed: false, marketing_suppressed_reason: nil)
    render json: { success: true, marketing_suppressed: false }
  end

  def dismiss_inactive
    user = current_tenant.users.find(params[:id])
    user.update_column(:inactive_dismissed_at, Time.current)
    render json: { success: true, inactive_dismissed_at: user.inactive_dismissed_at.iso8601 }
  end

  def create
    result = Users::Create.call(
      params: user_params.to_h.symbolize_keys,
      operator: current_tenant,
      admin_created: true
    )

    if result.success?
      render json: member_list_json(result.user), status: :created
    else
      render_error(result.error || 'Failed to create user')
    end
  end

  def update
    user = current_tenant.users.find(params[:id])

    if user.update(user_update_params)
      render json: member_list_json(user)
    else
      render_error(user.errors.full_messages.join(', '))
    end
  end

  def approve
    user = current_tenant.users.find(params[:id])
    user.update!(approved: true)

    # Activate pending subscription if one exists
    pending_sub = user.subscriptions.pending.first
    if pending_sub
      pending_sub.update!(pending: false, active: true)
    end

    SendNotificationsJob.perform_later(user)

    render json: { success: true, approved: true }
  end

  def unapprove
    user = current_tenant.users.find(params[:id])
    user.update!(approved: false)

    render json: { success: true, approved: false }
  end

  def archive
    user = current_tenant.users.find(params[:id])
    user.update!(archived: true)

    render json: { success: true, archived: true }
  end

  def unarchive
    user = current_tenant.users.find(params[:id])
    user.update!(archived: false)

    render json: { success: true, archived: false }
  end

  def add_credits
    user = current_tenant.users.find(params[:id])
    amount = params[:amount].to_i
    user.update!(credit_balance: user.credit_balance + amount)

    render json: { success: true, credit_balance: user.credit_balance }
  end

  def change_payment
    user = current_tenant.users.find(params[:id])

    case params[:payment_type]
    when 'card'
      user.update!(out_of_band: false, bill_to_organization: false)
    when 'out_of_band'
      user.update!(out_of_band: true, bill_to_organization: false)
    when 'bill_to_organization'
      user.update!(bill_to_organization: true, out_of_band: false)
    else
      return render_error('Invalid payment type')
    end

    render json: { success: true, payment_method: user.payment_method }
  end

  def assign_subscription
    user = current_tenant.users.find(params[:id])
    plan = Plan.find(params[:plan_id])

    subscription = Subscription.new(plan: plan, subscribable: user)

    begin
      result = Billing::Subscription::CreateSubscription.call(
        subscription: subscription,
        user: user,
        start_day: Date.current,
        operator: current_tenant,
        location: current_location,
      )

      if result.success?
        render json: { success: true, plan_name: plan.name }
      else
        render_error(result.message || 'Could not assign plan')
      end
    rescue Stripe::InvalidRequestError => e
      render_error("Stripe error: #{e.message}")
    rescue => e
      render_error(e.message)
    end
  end

  def create_day_pass
    user = current_tenant.users.find(params[:id])
    day_pass_type = DayPassType.find(params[:day_pass_type_id])

    result = Billing::DayPasses::CreateDayPass.call(
      user_id: user.id,
      operator: current_tenant,
      location: current_location,
      params: {
        day_pass_type: day_pass_type.id.to_s,
        day: params[:date] || Date.current,
        operator_id: current_tenant.id,
      },
    )

    if result.success?
      render json: { success: true, day_pass_type: day_pass_type.name }, status: :created
    else
      render_error(result.message || 'Could not create day pass')
    end
  end

  def create_reservation
    user = current_tenant.users.find(params[:id])
    room = Room.find(params[:room_id])
    datetime_in = Time.parse(params[:datetime_in])
    minutes = params[:minutes].to_i

    result = Billing::Reservations::CreateRoomReservation.call(
      reservation_params: {
        datetime_in: datetime_in,
        hours: minutes / 60.0,
        minutes: minutes,
        room: room,
      },
      user: user,
      location: current_location,
    )

    if result.success?
      render json: { success: true, room_name: room.name, time: datetime_in.strftime("%l:%M %p").strip }, status: :created
    else
      render_error(result.message || 'Could not create reservation')
    end
  end

  def edit_profile
    user = current_tenant.users.find(params[:id])
    permitted = params.permit(:name, :phone, :email, :bio, :linkedin, :twitter, :website)

    Searchkick.callbacks(false) do
      if user.update(permitted)
        render json: { success: true }
      else
        render_error(user.errors.full_messages.first)
      end
    end
  end

  def create_invoice
    user = current_tenant.users.find(params[:id])
    amount_in_cents = (params[:amount].to_f * 100).round
    description = params[:description]

    begin
      # Create Stripe invoice
      customer_id = user.stripe_customer_id_for_location(current_location)
      unless customer_id
        result = CreateStripeCustomer.call(user: user, location: current_location)
        customer_id = user.stripe_customer_id_for_location(current_location)
      end

      Stripe::InvoiceItem.create(
        { customer: customer_id, amount: amount_in_cents, currency: 'usd', description: description },
        { stripe_account: current_location.stripe_user_id }
      )
      stripe_invoice = Stripe::Invoice.create(
        { customer: customer_id },
        { stripe_account: current_location.stripe_user_id }
      )

      invoice = Invoice.create!(
        stripe_invoice_id: stripe_invoice.id,
        amount_due: amount_in_cents,
        status: 'open',
        billable: user,
        operator: current_tenant,
        location: current_location,
      )

      render json: { success: true, invoice_id: invoice.id }, status: :created
    rescue Stripe::StripeError => e
      render_error("Stripe error: #{e.message}")
    rescue => e
      render_error(e.message)
    end
  end

  def cancel_subscription
    user = current_tenant.users.find(params[:id])
    subscription = user.subscriptions.where(active: true).first
    return render_error('No active subscription') unless subscription

    result = SetSubscriptionForCancellation.call(
      subscription: subscription,
      blob: { text: "Admin cancelled #{user.name}'s #{subscription.plan.name} membership.", type: "membership_cancellation" },
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
      notifiable: current_tenant.users.admins,
    )

    if result.success?
      render json: { success: true }
    else
      render_error(result.message || 'Could not cancel subscription')
    end
  end

  def cancel_subscription_now
    user = current_tenant.users.find(params[:id])
    subscription = user.subscriptions.where(active: true).first
    return render_error('No active subscription') unless subscription

    begin
      result = Billing::Subscription::CancelSubscriptionNow.call(
        subscription: subscription,
        blob: { text: "Admin immediately cancelled #{user.name}'s #{subscription.plan.name} membership.", type: "membership_cancellation" },
        user: current_api_user,
        operator: current_tenant,
        location: current_location,
        notifiable: current_tenant.users.admins,
        creditable: user,
      )

      if result.success?
        render json: { success: true }
      else
        render_error(result.message || 'Could not cancel subscription')
      end
    rescue => e
      render_error(e.message)
    end
  end

  def reset_password
    user = current_tenant.users.find(params[:id])
    new_password = params[:new_password]

    if new_password.length < 6
      return render_error('Password must be at least 6 characters')
    end

    Searchkick.callbacks(false) do
      user.password = new_password
      user.save!(validate: false)
    end

    render json: { success: true }
  end

  def invoices
    user = current_tenant.users.find(params[:id])
    invoices = Invoice.where(billable: user, operator: current_tenant).order(created_at: :desc).limit(30)
    render json: invoices.map { |inv| {
      id: inv.id, amount_due: inv.amount_due, status: inv.status,
      description: inv.try(:description), pdf_url: inv.try(:pdf_url),
      created_at: inv.created_at.strftime("%B %e, %Y"),
    }}
  end

  def reservations
    user = current_tenant.users.find(params[:id])
    reservations = user.reservations.where(cancelled: false).order(datetime_in: :desc).limit(30)
    render json: reservations.map { |r| {
      id: r.id, room_name: r.room&.name, date: r.datetime_in.strftime("%B %e, %Y"),
      time: r.datetime_in.strftime("%l:%M %p").strip, minutes: r.minutes,
      cancelled: r.cancelled,
    }}
  end

  def checkins
    user = current_tenant.users.find(params[:id])
    checkins = user.checkins.order(created_at: :desc).limit(30)
    render json: checkins.map { |c| {
      id: c.id, date: c.created_at.strftime("%B %e, %Y"),
      time: c.created_at.strftime("%l:%M %p").strip,
      duration_minutes: c.try(:duration_minutes),
    }}
  end

  def usage
    user = current_tenant.users.find(params[:id])
    period_start = Time.current.beginning_of_month
    render json: {
      reservation_count: user.reservations.where(cancelled: false).where("datetime_in >= ?", period_start).count,
      reservation_minutes: user.reservations.where(cancelled: false).where("datetime_in >= ?", period_start).sum(:minutes),
      checkin_count: user.checkins.where("created_at >= ?", period_start).count,
      day_pass_count: user.day_passes.where("day >= ?", period_start.to_date).count,
      period: Time.current.strftime("%B %Y"),
    }
  end

  ACTIVITY_TABS = %w[recent emails tours reservations payments notes].freeze

  def activities
    user = current_tenant.users.find(params[:id])
    tab = ACTIVITY_TABS.include?(params[:tab]) ? params[:tab] : "recent"

    scope = user.activities.recent
    if tab != "recent"
      scope = scope.where(kind: ActivityTimelineHelper::KIND_GROUPS.fetch(tab))
    end

    render json: {
      tab: tab,
      activities: scope.limit(50).map { |a| activity_json(a) },
    }
  end

  def log_tour
    user = current_tenant.users.find(params[:id])

    activity = Activity.log(
      user: user,
      operator: current_tenant,
      kind: :tour,
      payload: {
        "notes" => params[:notes].to_s,
        "logged_by_user_id" => current_api_user.id,
      }
    )

    render json: {
      success: true,
      activity: {
        id: activity.id,
        occurred_at: activity.occurred_at.iso8601,
      },
    }, status: :created
  end

  def add_note
    user = current_tenant.users.find(params[:id])

    note = Note.new(
      notable: user,
      operator: current_tenant,
      author: current_api_user,
      body: params[:body],
    )

    if note.save
      render json: {
        success: true,
        note: {
          id: note.id,
          body: note.body.to_plain_text,
          author: current_api_user.name,
          created_at: note.created_at.iso8601,
        },
      }, status: :created
    else
      render_error(note.errors.full_messages.join(", "))
    end
  end

  private

  def activity_json(activity)
    {
      id: activity.id,
      kind: activity.kind,
      occurred_at: activity.occurred_at.iso8601,
      label: ApplicationController.helpers.activity_label(activity),
      icon: ActivityTimelineHelper::ICONS[activity.kind],
      payload: activity.payload || {},
    }
  end

  def search_users(scope)
    q = "%#{params[:q]}%"
    scope.where("users.name ILIKE ? OR users.email ILIKE ?", q, q)
  end

  def member_list_json(user)
    active_sub = user.subscriptions.find { |s| s.active? && !s.pending? }
    {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      approved: user.approved,
      plan_name: active_sub&.plan&.name,
      has_profile_photo: user.has_profile_photo?,
      marketing_suppressed: user.marketing_suppressed,
    }
  end

  def user_params
    params.permit(:name, :email, :phone, :password, :bio, :role)
  end

  def user_update_params
    params.permit(:name, :email, :phone, :bio, :role)
  end
end
