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
    # Scope to the admin's location to match the web approval queue
    # (users_helper#find_unapproved_users uses originally_at_location). Without
    # this, multi-location operators saw an operator-wide total on mobile and a
    # per-location total on web. For single-location operators it's a no-op.
    scope = current_tenant.users
                          .where(approved: false, archived: false)
                          .where.not(role: 'admin')
                          .originally_at_location(current_location)
                          .recent_signup # drop off after APPROVAL_QUEUE_DAYS -> cold leads
    scope = search_users(scope) if params[:q].present?

    # The list is paginated to 30, but the badge must reflect the TRUE total —
    # otherwise the app shows "30" while web shows the real count (e.g. 52).
    # Surfaced as a header so the response body stays a plain array (older app
    # builds keep working unchanged).
    response.set_header('X-Total-Count', scope.count.to_s)

    users = scope.order(created_at: :desc).offset(params[:offset].to_i).limit(30)
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
      # Bundle balance at the admin's location, for the +/- pass controls.
      bundle_passes_remaining: user.day_pass_bundles.active.where(location: current_location).sum(:passes_remaining),
      reservation_count: user.reservations.where(cancelled: false).count,
      invoice_count: Invoice.where(billable: user, operator: current_tenant).count,
      organization_id: user.organization_id,
      organization_name: user.try(:organization)&.try(:name),
      organization_owner: user.organization.present? && user.organization.owner_id == user.id,
      always_allow_building_access: user.always_allow_building_access,
      day_passes: user.day_passes.where(operator: current_tenant).order(day: :desc).limit(10).map { |dp|
        { id: dp.id, date: dp.day&.strftime("%B %e, %Y"), type_name: dp.day_pass_type&.name }
      },
      marketing_suppressed: user.marketing_suppressed,
      marketing_suppressed_reason: user.marketing_suppressed_reason,
      inactive_dismissed_at: user.inactive_dismissed_at&.iso8601,
      point_of_contact_id: user.point_of_contact_id,
      point_of_contact_name: user.point_of_contact&.name,
      interest_tags: interest_tags_json(user),
    }
  end

  # Staff manually tag/untag a Person's product interest (ADR 0022) — source
  # "staff", sticky. The office tag feeds the Office queue. Mirrors the web
  # Operator::UsersController#add_interest / #remove_interest.
  def add_interest
    user = current_tenant.users.find(params[:id])

    if InterestTag.record(user: user, product: params[:product], source: "staff", added_by: current_api_user)
      render json: { success: true, interest_tags: interest_tags_json(user) }
    else
      render_error("That isn't a product we track interest in.")
    end
  end

  def remove_interest
    user = current_tenant.users.find(params[:id])
    user.interest_tags.for_product(params[:product].to_s).destroy_all
    render json: { success: true, interest_tags: interest_tags_json(user) }
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

  # Put the member in a group (organization). Mirrors the web "Update group"
  # form (Operator::UsersController#update_organization). The organization is
  # looked up through current_tenant so a member can never be attached to
  # another operator's group.
  def assign_organization
    user = current_tenant.users.find(params[:id])
    organization = current_tenant.organizations.find_by(id: params[:organization_id])
    return render_error('Group not found', status: :not_found) unless organization

    if user.update(organization: organization)
      render json: {
        success: true,
        organization_id: organization.id,
        organization_name: organization.name,
      }
    else
      render_error(user.errors.full_messages.join(', '))
    end
  end

  def remove_organization
    user = current_tenant.users.find(params[:id])
    # bill_to_organization with no organization is a broken billing state —
    # the subscription guard (SaveSubscription) would treat the member as
    # billable with nowhere to send the invoice. Clear it with the membership.
    user.update!(organization: nil, bill_to_organization: false)
    render json: { success: true }
  end

  def create
    return unless authorize_requested_role!

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
    return unless authorize_requested_role!(user.role)

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
    Activity.log_admin_action(user: user, actor: current_api_user, operator: current_tenant, action: :approved)

    render json: { success: true, approved: true }
  end

  def unapprove
    user = current_tenant.users.find(params[:id])
    user.update!(approved: false)
    Activity.log_admin_action(user: user, actor: current_api_user, operator: current_tenant, action: :unapproved)

    render json: { success: true, approved: false }
  end

  def archive
    user = current_tenant.users.find(params[:id])
    user.update!(archived: true)
    Activity.log_admin_action(user: user, actor: current_api_user, operator: current_tenant, action: :archived)

    render json: { success: true, archived: true }
  end

  def unarchive
    user = current_tenant.users.find(params[:id])
    user.update!(archived: false)
    Activity.log_admin_action(user: user, actor: current_api_user, operator: current_tenant, action: :unarchived)

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

  # NOTE: current_location is the admin's home location — acceptable for
  # single-location operators; revisit if multi-location admin scheduling is added.
  def schedule_bundle_days
    member = current_tenant.users.find(params[:id])
    location = current_location
    result = Billing::DayPassBundles::ScheduleDays.call(
      user: member, location: location, dates: Array(params[:dates]), performed_by: current_api_user)

    if result.outcome == :scheduled
      render json: {
        status: "scheduled",
        scheduled_days: result.day_passes.map { |dp| dp.day.iso8601 },
        passes_remaining: member.day_pass_bundles.active.where(location: location).sum(:passes_remaining),
      }
    else
      render_error(schedule_error_message(member, result))
    end
  end

  # NOTE: current_location is the admin's home location — acceptable for
  # single-location operators; revisit if multi-location admin scheduling is added.
  def scheduled_bundle_days
    member = current_tenant.users.find(params[:id])
    location = current_location
    tz = ActiveSupport::TimeZone[location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    # includes(office_hold: :room): office_room below would otherwise fire two
    # queries per scheduled day. Reservation's default_scope keeps a released
    # hold out of the preload, so a pass whose office was freed reads as nil.
    passes = member.day_passes.bundle_sourced.for_location(location).where("day > ?", today)
                   .includes(office_hold: :room).order(:day)
    render json: passes.map { |dp|
      {
        id: dp.id,
        day: dp.day.iso8601,
        date: dp.day.strftime("%B %e, %Y"),
        # Additive (ADR 0026): the room name for a Day Office pass, nil for a
        # standard one and for an office pass staff scheduled into a full pool.
        office_room: dp.office_hold&.room&.name,
        # Additive (Task 16): lets the mobile admin UI target the reassign
        # endpoints (which key off the Reservation/hold id), nil under the
        # same conditions as office_room above.
        office_hold_id: dp.office_hold&.id,
      }
    }
  end

  def cancel_scheduled_bundle_day
    member = current_tenant.users.find(params[:member_id])
    location = current_location
    day_pass = member.day_passes.find(params[:id])
    result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: current_api_user)
    if result.outcome == :cancelled
      render json: {
        status: "cancelled",
        passes_remaining: member.day_pass_bundles.active.where(location: location).sum(:passes_remaining),
      }
    else
      message = case result.outcome
                when :too_late then "That day is already today or past — too late to cancel it."
                when :not_scheduled then "That pass didn't come from a bundle."
                else "Could not cancel that day (#{result.outcome})."
                end
      render_error(message)
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  # Admin spends one bundle pass with no date attached (kind: admin_burn).
  # No DayPass is minted — no door access, no coverage, and it can't suppress
  # a real entry burn later the same day. Draws from the same pack ScheduleDay
  # would: soonest-expiring active at the admin's location.
  def burn_bundle_pass
    member = current_tenant.users.find(params[:id])
    location = current_location
    bundle = member.day_pass_bundles.active.where(location: location)
                   .order(Arel.sql("expires_at ASC NULLS LAST, created_at ASC")).first
    return render_error("No active pack with passes left.") if bundle.nil?

    bundle.burn!(kind: :admin_burn, performed_by: current_api_user,
                 guest_name: params[:reason].presence || "admin burn (mobile)")
    render json: {
      status: "burned",
      passes_remaining: member.day_pass_bundles.active.where(location: location).sum(:passes_remaining),
    }
  rescue DayPassBundle::NoPassesRemaining
    render_error("No passes left in that pack.")
  end

  # +1 counterpart (kind: admin_restore): returns a pass to the pack the burn
  # pick would draw from — soonest-expiring, not expired, below capacity. The
  # below-capacity filter (rather than `active`) is what makes undoing the burn
  # that emptied a pack work.
  def restore_bundle_pass
    member = current_tenant.users.find(params[:id])
    location = current_location
    bundle = member.day_pass_bundles.where(location: location)
                   .where("expires_at IS NULL OR expires_at > ?", Time.current)
                   .where("passes_remaining < quantity_purchased")
                   .order(Arel.sql("expires_at ASC NULLS LAST, created_at ASC")).first
    return render_error("No pack has room for a pass back.") if bundle.nil?

    if bundle.restore!(by: current_api_user, reason: params[:reason].presence || "admin add-back (mobile)")
      render json: {
        status: "restored",
        passes_remaining: member.day_pass_bundles.active.where(location: location).sum(:passes_remaining),
      }
    else
      render_error("That pack is already full.")
    end
  end

  def create_day_pass
    user = current_tenant.users.find(params[:id])
    day_pass_type = DayPassType.find(params[:day_pass_type_id])

    # comp: on the house — no invoice, no charge, pass flagged complimentary.
    # Same flag the web admin form sends; staff-only endpoint.
    result = Billing::DayPasses::CreateDayPass.call(
      user_id: user.id,
      operator: current_tenant,
      location: current_location,
      comp: ActiveModel::Type::Boolean.new.cast(params[:comp]) == true,
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

    # comp: staff books the room on the house — no credits burned, no charge
    # captured, no coverage pass consumed. The member still gets confirmation
    # emails and reservation-window door access.
    result = Billing::Reservations::CreateRoomReservation.call(
      reservation_params: {
        datetime_in: datetime_in,
        hours: minutes / 60.0,
        minutes: minutes,
        room: room,
      },
      user: user,
      location: current_location,
      comp: ActiveModel::Type::Boolean.new.cast(params[:comp]) || false,
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
        { api_key: current_location.stripe_secret_key, stripe_account: current_location.stripe_user_id }
      )
      stripe_invoice = Stripe::Invoice.create(
        { customer: customer_id },
        { api_key: current_location.stripe_secret_key, stripe_account: current_location.stripe_user_id }
      )

      invoice = Invoice.create!(
        stripe_invoice_id: stripe_invoice.id,
        amount_due: amount_in_cents,
        status: 'open',
        billable: user,
        operator: current_tenant,
        location: current_location,
        # Revenue is keyed on COALESCE(due_date, date) — a dateless row
        # would never count even after it's marked paid.
        date: Time.current,
        description: description,
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
      # When a member taps "End reservation now," the model writes
      # ended_early=true and rewrites `minutes` to the actual time used.
      # The admin's mobile list was rendering only room/date/time/minutes,
      # so an ended-early booking looked identical to a still-active one
      # — admins thought a paid reservation was running when the user had
      # already walked out. Surface the flag so the client can badge it.
      ended_early: r.ended_early,
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
      visit_days: Jellyswitch::UsageReport.new(user).days_used_count,
      period: Time.current.strftime("%B %Y"),
    }
  end

  ACTIVITY_TABS = %w[recent emails tours reservations payments notes doors].freeze

  def activities
    user = current_tenant.users.find(params[:id])
    tab = ACTIVITY_TABS.include?(params[:tab]) ? params[:tab] : "recent"

    scope =
      if tab == "recent"
        # Hides door_punch noise (keeps only milestone punches). See User.
        user.recent_timeline_activities(limit: 50)
      else
        user.activities.recent.where(kind: ActivityTimelineHelper::KIND_GROUPS.fetch(tab)).limit(50)
      end

    activities = scope.to_a
    hours = TimelineHoursIndex.build(user: user, activities: activities)

    render json: {
      tab: tab,
      activities: activities.map { |a| activity_json(a, hours) },
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

  # #6: a member's past chat/feedback threads, surfaced on their admin page.
  # Replies are inlined so the mobile Chat tab renders full threads in one call.
  def conversations
    user = current_tenant.users.find(params[:id])

    feedbacks = MemberFeedback
      .where(operator: current_tenant, user_id: user.id)
      .order(updated_at: :desc)
      .limit(50)

    render json: feedbacks.map { |f|
      {
        id: f.id,
        body: f.comment,
        rating: f.rating,
        dismissed: f.dismissed_at.present?,
        created_at: f.created_at.iso8601,
        updated_at: f.updated_at.iso8601,
        replies: f.feedback_replies.order(:created_at).map { |r|
          {
            id: r.id,
            body: r.body,
            author: r.user&.name,
            is_admin: r.from_admin?,
            created_at: r.created_at.iso8601,
          }
        },
      }
    }
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

  # Raw interactor outcomes read like debug output in the staff-facing alert
  # ("already_covered") — translate them. ScheduleDays coerces failed_date to a
  # Date on every failure except an unparseable :invalid_date, so only the
  # non-:invalid_date branches format it.
  def schedule_error_message(member, result)
    case result.outcome
    when :already_covered
      "#{member.name} already has coverage for #{result.failed_date.strftime('%b %-d')} — nothing was burned."
    when :no_bundle
      "#{member.name} has no bundle pass available for #{result.failed_date.strftime('%b %-d')}."
    when :invalid_date
      "Pick a date between today and #{Billing::DayPassBundles::ScheduleDay::HORIZON_DAYS} days out."
    else
      "Could not schedule those days (#{result.outcome})."
    end
  end

  def interest_tags_json(user)
    user.interest_tags.order(:product).map { |tag| { product: tag.product, source: tag.source } }
  end

  # `subtitle` is rendered server-side so mobile and web read identically and
  # the app never has to redo the room-zone date math. Older builds ignore it
  # and keep formatting occurred_at themselves.
  def activity_json(activity, hours = nil)
    {
      id: activity.id,
      kind: activity.kind,
      occurred_at: activity.occurred_at.iso8601,
      label: ApplicationController.helpers.activity_label(activity),
      subtitle: ApplicationController.helpers.activity_timeline_subtitle(activity, hours: hours),
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

  # Server-side ceiling on role grants — the web edit form enforces this by
  # only offering roles in current_user.role_options_for_select, but the API
  # took whatever :role was sent, letting any admin-API caller (down to a
  # community manager) escalate anyone — or themselves — to superadmin. Renders
  # 403 and returns false when the requested role exceeds what the caller may
  # grant. A request that omits :role, or leaves the target's role unchanged,
  # is always allowed (so ordinary profile edits on a higher-role member still
  # work). Returns true when the action may proceed.
  def authorize_requested_role!(current_role = nil)
    requested = params[:role].presence
    return true if requested.nil? || requested == current_role
    return true if current_api_user.can_assign_role?(requested)

    render_error("You are not allowed to assign the #{requested.titleize} role.", status: :forbidden)
    false
  end
end
