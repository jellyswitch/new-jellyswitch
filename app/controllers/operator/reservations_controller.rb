class Operator::ReservationsController < Operator::BaseController
  # Runs first: un-mangle any `amp;`-prefixed params before set_reserved_user
  # or the actions try to read room_id/user_id. See
  # Operator::BaseController#recover_html_escaped_query_params for the why.
  prepend_before_action :recover_html_escaped_query_params

  before_action :require_authentication
  before_action :background_image, except: [:reserve_now, :reserve_now_price]
  before_action :set_reserved_user, only: [:choose_day, :choose_time_post, :choose_time, :choose_duration, :confirm, :create_reservation]

  # Telemetry: when `current_tenant.rooms.find(params[:room_id])` (or any
  # other `find!`) in this controller raises RecordNotFound, the user sees
  # a generic Rails 404 with no breadcrumb to debug from. Capture full
  # request context to Honeybadger before re-raising so the 404 still
  # renders unchanged. Defined on Operator::BaseController.
  rescue_from ActiveRecord::RecordNotFound, with: :report_record_not_found_with_context

  include ActionView::Helpers::NumberHelper
  include ReservationHelper
  include CreditHelper

  def show
    find_reservation
    authorize @reservation
    @reservation = @reservation.decorate
    background_image
  end

  def choose_member
    authorize :reservation
    @room = current_tenant.rooms.find(params[:room_id])
    @next_step_path = params[:day].present? && params[:hour].present? ? choose_duration_reservations_path : choose_day_reservations_path
    all_options = User.lease_options_for_select(current_tenant, current_location)

    # Filter to eligible members only
    eligible = Set.new([current_user.id])

    # Admins/managers
    begin
      eligible.merge(User.for_space(current_tenant).where(role: [User::ADMIN, User::GENERAL_MANAGER, User::COMMUNITY_MANAGER]).pluck(:id))
    rescue => e
      Rails.logger.error("choose_member admins error: #{e.class}: #{e.message}")
    end

    # Active subscribers (subscribable is polymorphic — subscribable_type "User" means subscribable_id is the user_id)
    begin
      plan_ids = Plan.where(location_id: current_location.id).pluck(:id)
      if plan_ids.any?
        eligible.merge(Subscription.where(active: true, plan_id: plan_ids, subscribable_type: "User").pluck(:subscribable_id))
      end
    rescue => e
      Rails.logger.error("choose_member subscribers error: #{e.class}: #{e.message}")
    end

    # Organization subscribers — orgs with active subscriptions, then their member user IDs
    begin
      if plan_ids.present? && plan_ids.any?
        org_ids = Subscription.where(active: true, plan_id: plan_ids, subscribable_type: "Organization").pluck(:subscribable_id)
        eligible.merge(User.for_space(current_tenant).where(organization_id: org_ids).pluck(:id)) if org_ids.any?
      end
    rescue => e
      Rails.logger.error("choose_member org_subscribers error: #{e.class}: #{e.message}")
    end

    # Organization members with active office leases at this location
    begin
      lease_org_ids = OfficeLease.active.where(location_id: current_location.id).pluck(:organization_id)
      eligible.merge(User.for_space(current_tenant).where(organization_id: lease_org_ids).pluck(:id)) if lease_org_ids.any?
    rescue => e
      Rails.logger.error("choose_member lease_members error: #{e.class}: #{e.message}")
    end

    # Day pass holders (today or future)
    begin
      eligible.merge(DayPass.where("day >= ?", Time.current.to_date).pluck(:user_id))
    rescue => e
      Rails.logger.error("choose_member day_passes error: #{e.class}: #{e.message}")
    end

    # Users with current or future reservations
    begin
      eligible.merge(Reservation.where("datetime_in >= ?", Time.current).pluck(:user_id))
    rescue => e
      Rails.logger.error("choose_member reservations error: #{e.class}: #{e.message}")
    end

    all_options = all_options.select { |_name, id| eligible.include?(id) } if eligible.size > 1

    admin_option = all_options.find { |_name, id| id == current_user.id }
    admin_option ||= [current_user.name, current_user.id]
    others = all_options.reject { |_name, id| id == current_user.id }
    @member_options = [admin_option] + others
  end

  def choose_day
    # requires room, user
    @room = current_tenant.rooms.find(params[:room_id])
  end

  def choose_time_post
    @room = current_tenant.rooms.find(params[:room_id])
    @day = parsed_day_param
    if @day.nil?
      redirect_to choose_day_reservations_path(room_id: @room.id, user_id: @user.id),
                  alert: "Please pick a date before continuing." and return
    end
    turbo_redirect choose_time_reservations_path(room_id: @room.id, user_id: @user.id, day: @day)
  end

  def choose_time
    # requires room, user, day
    @room = current_tenant.rooms.find(params[:room_id])
    @day = parsed_day_param
    if @day.nil?
      redirect_to choose_day_reservations_path(room_id: @room.id, user_id: @user.id),
                  alert: "Please pick a date before continuing." and return
    end
  end

  def choose_duration
    # require room, user, day, time
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @staff = staff

    parse_time
  end

  def confirm
    # requires room, user, day, time, duration
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @duration = params[:duration].to_i

    @staff = staff

    parse_time
    should_charge = @user.should_charge_for_reservation?(current_location, @day)

    # Check subscription overage
    if !should_charge && @duration.present?
      begin
        sub_info = @user.subscription_reservation_charge_info(current_location, @duration)
        should_charge = true if sub_info && sub_info[:charge_type] == :partial_overage
      rescue => e
        Rails.logger.error("subscription_reservation_charge_info error in confirm: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
      end
    end

    if should_charge || !@user.has_billing_for_location?(current_location)
      include_stripe
    end
  end

  def update_billing_and_create_reservation
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @duration = params[:duration].to_i

    parse_time

    token = params[:stripeToken]

    result = Billing::Reservations::UpdateBillingAndCreateRoomReservation.call(reservation_params: {
                                                                                 datetime_in: @datetime_in,
                                                                                 hours: @duration,
                                                                                 minutes: @duration.to_i,
                                                                                 room: @room,
                                                                               }, user: current_user,
                                                                               location: current_location,
                                                                               token: token,
                                                                               out_of_band: false,
                                                                               # Posted-hours backstop (Nash incident), same booker gate as
                                                                               # the cap below: members/leaseholders stay exempt inside
                                                                               # EnforcePostedHours (books 24/7), so this only bites
                                                                               # non-members hand-rolling wizard POSTs.
                                                                               enforce_posted_hours: !current_user.admin_or_manager?(current_location),
                                                                               # Duration backstop, gated on the booker like the API's
                                                                               # staff_booker? (this endpoint books for current_user, so
                                                                               # booker == booked): staff keep the 12h admin allowance.
                                                                               enforce_duration_cap: !current_user.admin_or_manager?(current_location),
                                                                               # Included-room coverage (ADR 0019), same gate as
                                                                               # create_reservation below: a non-member bundle holder has
                                                                               # should_charge_for_reservation? true, so with no card on file
                                                                               # the confirm page routes them HERE — the same wizard hole.
                                                                               # No decision flags are sent: bundle holders burn
                                                                               # automatically (ADR 0029), non-holders get EnforceCoverage's
                                                                               # buy prompt.
                                                                               enforce_coverage: !current_user.admin_or_manager?(current_location))
    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      track_conversion("room_reservation",
                       product_name: @reservation.room&.name,
                       amount_in_cents: @reservation.captured_amount_in_cents,
                       transaction_id: "res_#{@reservation.id}")
      if current_user.approved?
        turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
      else
        turbo_redirect(wait_path, action: restore_if_possible)
      end
    else
      flash[:error] = result.message
      if current_user.approved?
        turbo_redirect(confirm_reservations_path(room_id: @room.id, day: @day, hour: pretty_time(@hour), duration: @duration), action: "replace")
      else
        turbo_redirect(wait_path, action: restore_if_possible)
      end
    end
  end

  def create_reservation
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @duration = params[:duration].to_i
    parse_time

    # Compute subscription overage info for members
    begin
      subscription_charge_info = @user.subscription_reservation_charge_info(current_location, @duration)
    rescue => e
      Rails.logger.error("subscription_reservation_charge_info error in create_reservation: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
      subscription_charge_info = nil
    end

    # Staff-only comp (mirrors the mobile admin flow): the confirm page offers
    # "Comp — book free of charge" when staff book for someone else. Members
    # can't comp themselves — a forged comp param from a non-staff session is
    # ignored here.
    comp = staff && params[:comp].present?

    result = Billing::Reservations::CreateRoomReservation.call(reservation_params: {
                                                                 datetime_in: @datetime_in,
                                                                 hours: @duration,
                                                                 minutes: @duration.to_i,
                                                                 room: @room,
                                                               }, user: @user, location: current_location,
                                                               subscription_charge_info: subscription_charge_info,
                                                               comp: comp,
                                                               # Posted-hours backstop (Nash incident), gated on the BOOKER like
                                                               # the cap below: staff on-behalf bookings may book anything, and
                                                               # for non-staff @user == current_user (set_reserved_user), so the
                                                               # interactor's member/leaseholder 24/7 exemption lands on the
                                                               # right person. Only non-members hand-rolling wizard POSTs are hit.
                                                               enforce_posted_hours: !current_user.admin_or_manager?(current_location),
                                                               # Cap gated on the BOOKER, not @user: the interactor reads the
                                                               # cap from context.user (the booked member), so the flag must
                                                               # stay off when staff book on behalf — the member's 4h free-room
                                                               # cap must not block a staff booking (12h admin allowance).
                                                               enforce_duration_cap: !current_user.admin_or_manager?(current_location),
                                                               # Non-payment cutoff, gated on the BOOKER the same way: staff
                                                               # may still book on behalf of a suspended member (admin bypass).
                                                               enforce_payment_standing: !current_user.admin_or_manager?(current_location),
                                                               # Included-room coverage (ADR 0019), same BOOKER gate: without it a
                                                               # member could book a $0 include_with_day_pass room through this
                                                               # wizard with no pass committed — free room, no bundle burn, no
                                                               # building access that day. The wizard confirm page carries no
                                                               # coverage UI, so no decision flags are sent: bundle holders burn
                                                               # automatically (ADR 0029) and non-holders get EnforceCoverage's
                                                               # buy prompt. Staff on-behalf stays unenforced — an operator may
                                                               # still book an uncovered included room.
                                                               enforce_coverage: !current_user.admin_or_manager?(current_location))

    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}#{" — comped, no charge" if comp}"
      redirect_to reservation_path(@reservation)
    else
      flash[:error] = result.message
      redirect_to confirm_reservations_path(room_id: @room.id, day: @day, hour: pretty_time(@hour), duration: @duration)
    end
  end

  def destroy
    find_reservation
    authorize @reservation, :cancel?

    # ReservationPolicy#cancel? admits `owner?`, so this action is member-facing
    # too — a member reaches it for their own bookings. A Day Office hold is not
    # one of those: it's the office their pass entitles them to (ADR 0026), and
    # self-cancelling would release the room while leaving the pass sold and
    # spent. Staff keep the ability to cancel a hold (the reassign/refund tools
    # are theirs), so this gates on the CALLER being non-staff, not on the mode
    # below — which is :admin for every caller of this action.
    if @reservation.day_office_hold? && !current_user.admin_or_manager?(current_location)
      flash[:error] = "Your office comes with your Day Office pass — ask staff to change or refund it."
      return turbo_redirect(referrer_or_root)
    end

    # Operator/staff cancel = admin mode: refunds all the reservation's invoices
    # regardless of the member cancellation window (ADR 0011).
    result = CancelReservation.call(reservation: @reservation, mode: :admin)

    if result.success?
      flash[:notice] = "Reservation cancelled."
      turbo_redirect(root_path)
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root)
    end
  rescue Pundit::NotAuthorizedError
    # Stale-tab race: Cancel was visible when the reservation was future,
    # but it has since started or ended (so policy.cancel? now returns
    # false). Route the user toward the right action and skip the
    # Honeybadger notify — this is expected, not a bug.
    if @reservation&.ongoing?
      flash[:notice] = "This reservation has already started. Use \"End reservation now\" to release the room early."
      turbo_redirect(reservation_path(@reservation))
    else
      flash[:error] = "This reservation has already ended and can no longer be cancelled."
      turbo_redirect(referrer_or_root)
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def today
    authorize Reservation
    @rooms = find_todays_reservations(current_location)
  end

  # New 'Reservation Now' flow

  def calendar
    include_stripe
    @current_date = Time.zone.today
    if params[:reserve_now]
      @nearest_time_slot = calculate_nearest_time_slot(@current_date)
      @day_or_night = @nearest_time_slot.hour < 12 ? "day" : "night" if @nearest_time_slot
      @is_reserve_now = true
    end
    background_image
  end

  def available_time_slots
    if params[:day].present? && params[:day_or_night].present?
      @day = Date.parse(params[:day])
      @day_or_night = params[:day_or_night]

      if @day_or_night == "all"
        @available_time_slots = calculate_all_available_time_slots(@day)
        render json: @available_time_slots.map { |slot| slot.strftime("%I:%M %p") }
      else
        @available_time_slots = calculate_available_time_slots(@day, @day_or_night)
        render json: @available_time_slots.map { |slot| slot.strftime("%I:%M") }
      end
    else
      render json: { error: "Invalid date or day/night selection" }, status: :unprocessable_entity
    end
  end

  def available_rooms
    if params[:date].present? && params[:time].present? && params[:duration].present?
      date = params[:date]

      day_or_night = params[:day_or_night]
      time = params[:time]
      time += " pm" if day_or_night == "night"

      duration = params[:duration]

      parsed_date = Time.zone.parse(date)
      include_hidden = current_user.admin_or_manager?(current_location)
      available_rooms = current_location.rooms.available(date: date, time: time, duration: duration, include_hidden: include_hidden)

      if !current_user.can_see_all_rooms?(current_location, parsed_date)
        available_rooms = available_rooms.rentable
      end

      render json: available_rooms, only: [:id, :name, :photo, :capacity, :hourly_rate_in_cents]
    else
      render json: { error: "Invalid or missing parameters" }, status: :unprocessable_entity
    end
  end

  def max_available_duration
    if params[:date].present? && params[:time].present? && params[:day_or_night].present?
      date = params[:date]
      day_or_night = params[:day_or_night]
      time = params[:time]
      time += " pm" if day_or_night == "night"

      parsed_date = Date.parse(date)
      parsed_time = Time.zone.parse("#{date} #{time}")

      rooms = current_user.admin_or_manager?(current_location) ? current_location.rooms.active : current_location.rooms.visible
      rooms = rooms.rentable unless current_user.can_see_all_rooms?(current_location, parsed_date)

      # Per-room policy cap (staff 12h; priced rooms 12h; free rooms 4h)
      # instead of the old flat 480 — the web admin was stuck at 8h while
      # mobile admin allowed 12h.
      booking_admin = current_user.admin_or_manager?(current_location)
      max_duration = 0
      rooms.each do |room|
        cap = room.max_bookable_minutes(admin: booking_admin)
        durations = room.calculate_max_continuous_duration(start_time: parsed_time, max_minutes: cap)
        max_duration = [max_duration, durations].max
      end

      render json: { max_duration: max_duration }
    else
      render json: { error: "Invalid parameters" }, status: :unprocessable_entity
    end
  end

  def room_price_and_details
    if params[:room_id].present? && params[:duration].present? && params[:date].present?
      room = Room.find(params[:room_id])
      duration = params[:duration].to_i
      date = Time.zone.parse(params[:date])

      # Priced (premium) rooms charge everyone EXCEPT members/leaseholders/staff —
      # day-passers are NOT exempt (a day pass covers free rooms + included minutes,
      # not hourly rooms). $0 rooms use reservation-level coverage. Matches
      # should_charge_for_room? + the actual booking charge, so the quote can never
      # read "Free" for a room the booker is charged for.
      priced_room = room.hourly_rate_in_cents.to_i > 0
      should_charge = priced_room ?
        current_user.should_charge_for_room?(room, date) :
        current_user.should_charge_for_reservation?(current_location, date)

      hourly_price = room.hourly_rate_in_cents / 100.0
      reservation_price = should_charge ? (room.hourly_rate_in_cents / 100.0 * (duration / 60.0)) : 0

      # Day-pass / subscription included-minutes never cover a premium hourly room,
      # so skip those adjustments for priced rooms (they'd wrongly re-zero them).
      begin
        day_pass_charge_info = priced_room ? nil : current_user.day_pass_reservation_charge_info(current_location, date.to_date, duration)
      rescue => e
        Rails.logger.error("day_pass_reservation_charge_info error: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
        day_pass_charge_info = nil
      end

      response = {
        id: room.id,
        name: room.name,
        hourly_price: hourly_price,
        capacity: room.capacity,
        reservation_price: reservation_price,
        should_charge: should_charge,
        coverage_label: (should_charge ? nil : (
          current_user.member?(current_location) ? "Included with membership" :
          current_user.has_active_lease? ? "Included with office" :
          current_user.has_active_day_pass?(date.to_date) ? "Included with day pass" : "Free"
        )),
        is_day_pass_overage: false,
        amenities: room.amenities,
      }

      if day_pass_charge_info
        if day_pass_charge_info[:charge_type] == :partial_overage
          response[:should_charge] = true
          response[:is_day_pass_overage] = true
          response[:reservation_price] = day_pass_charge_info[:overage_amount_in_cents] / 100.0
          response[:included_minutes_remaining] = day_pass_charge_info[:remaining_free]
          response[:overage_minutes] = day_pass_charge_info[:overage_minutes_rounded]
          response[:overage_rate_hourly] = day_pass_charge_info[:overage_rate_in_cents] / 100.0
        else
          response[:should_charge] = false
          response[:reservation_price] = 0
          response[:included_minutes_remaining] = day_pass_charge_info[:remaining_free]
        end
      end

      # Check subscription meeting room overage for members
      begin
        subscription_charge_info = priced_room ? nil : current_user.subscription_reservation_charge_info(current_location, duration)
      rescue => e
        Rails.logger.error("subscription_reservation_charge_info error: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
        subscription_charge_info = nil
      end

      if subscription_charge_info
        if subscription_charge_info[:charge_type] == :partial_overage
          response[:should_charge] = true
          response[:is_subscription_overage] = true
          response[:reservation_price] = subscription_charge_info[:overage_amount_in_cents] / 100.0
          response[:included_minutes_remaining] = subscription_charge_info[:remaining_free]
          response[:overage_minutes] = subscription_charge_info[:overage_minutes_rounded]
          response[:overage_rate_hourly] = subscription_charge_info[:overage_rate_in_cents] / 100.0
          response[:used_minutes] = subscription_charge_info[:used_minutes]
          response[:included_minutes] = subscription_charge_info[:included_minutes]
        elsif !day_pass_charge_info
          response[:should_charge] = false
          response[:reservation_price] = 0
          response[:included_minutes_remaining] = subscription_charge_info[:remaining_free]
          response[:used_minutes] = subscription_charge_info[:used_minutes]
          response[:included_minutes] = subscription_charge_info[:included_minutes]
        end
      end

      render json: response
    else
      render json: { error: "Invalid or missing parameters" }, status: :unprocessable_entity
    end
  end

  def create
    reservation_params = create_reservation_params

    @room = current_tenant.rooms.find(reservation_params[:room_id])
    @day = Date.parse(reservation_params[:date])

    @day_or_night = reservation_params[:day_or_night]
    @hour = Time.strptime(reservation_params[:time], "%I:%M")

    amenity_ids = params[:amenity_ids] || []

    # Adjust for AM/PM
    if @day_or_night == "night" && @hour.hour != 12
      @hour += 12.hours
    elsif @day_or_night == "day" && @hour.hour == 12
      @hour -= 12.hours
    end

    @duration = reservation_params[:duration].to_i
    parse_time

    token = params[:stripeToken]

    # Compute day pass overage info for the interactor chain
    begin
      day_pass_charge_info = current_user.day_pass_reservation_charge_info(current_location, @day, @duration)
    rescue => e
      Rails.logger.error("day_pass_reservation_charge_info error in create: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
      day_pass_charge_info = nil
    end

    # Compute subscription overage info
    begin
      subscription_charge_info = current_user.subscription_reservation_charge_info(current_location, @duration)
    rescue => e
      Rails.logger.error("subscription_reservation_charge_info error in create: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
      subscription_charge_info = nil
    end

    # Validate discount code if provided
    discount_code = nil
    if params[:discount_code].present?
      validate_result = Billing::DiscountCodes::ValidateCode.call(
        code: params[:discount_code],
        location: current_location,
        product_type: "meeting_room"
      )
      if validate_result.success?
        discount_code = validate_result.discount_code
      else
        flash[:error] = validate_result.message
        turbo_redirect(calendar_reservations_path, action: "replace")
        return
      end
    end

    interactor = if token.present?
      Billing::Reservations::UpdateBillingAndCreateRoomReservation
    else
      Billing::Reservations::CreateRoomReservation
    end

    # Included-room coverage (ADR 0019): forward the member's confirm decision so
    # the organizer reuses a spare pass / burns a bundle pass / buys one, and
    # enforce_coverage blocks the booking if an included room stays uncovered.
    # Member self-service (books for current_user) — mirrors the mobile API.
    use_bundle_pass   = ActiveModel::Type::Boolean.new.cast(params[:use_bundle_pass])
    use_existing_pass = ActiveModel::Type::Boolean.new.cast(params[:use_existing_pass])
    buy_day_pass      = ActiveModel::Type::Boolean.new.cast(params[:buy_day_pass])
    coverage_day_pass_type = Billing::Reservations::CoverageState.for(
      user: current_user, room: @room, date: @day, location: current_location).day_pass_type

    result = interactor.call(reservation_params: {
                               datetime_in: @datetime_in,
                               hours: @duration / 60,
                               minutes: @duration.to_i,
                               room: @room,
                               amenity_ids: amenity_ids,
                               note: reservation_params[:note],
                               attendee_count: reservation_params[:attendee_count].presence,
                             }, user: current_user, location: current_location,
                             token: token, out_of_band: false,
                             day_pass_charge_info: day_pass_charge_info,
                             subscription_charge_info: subscription_charge_info,
                             use_bundle_pass: use_bundle_pass,
                             use_existing_pass: use_existing_pass,
                             buy_day_pass: buy_day_pass,
                             day_pass_type: coverage_day_pass_type,
                             enforce_coverage: true,
                             enforce_posted_hours: true,
                             # Non-payment cutoff (PaymentCutoff); no-op for staff.
                             enforce_payment_standing: true,
                             # Server-side duration cap (member self-serve only;
                             # the staff calendar flows keep the admin allowance).
                             enforce_duration_cap: true,
                             discount_code: discount_code)

    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      track_conversion("room_reservation",
                       product_name: @reservation.room&.name,
                       amount_in_cents: @reservation.captured_amount_in_cents,
                       transaction_id: "res_#{@reservation.id}")
      turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
    else
      flash[:error] = result.message
      turbo_redirect(calendar_reservations_path, action: "replace")
    end
  end

  def available_extension_durations
    reservation = Reservation.find(params[:id])
    room = reservation.room

    available_durations = room.calculate_available_durations(start_time: reservation.datetime_out)

    render json: available_durations
  end

  def calculate_additional_hour_price
    reservation = Reservation.find(params[:id])
    room = reservation.room

    additional_duration = params[:duration].to_i
    additional_price = number_to_currency((room.hourly_rate_in_cents / 100.0) * (additional_duration / 60.0))

    reservation.assign_attributes({ minutes: reservation.minutes + additional_duration })

    render json: {
      additional_price: additional_price,
      new_end_time: reservation.datetime_out.strftime("%m/%d/%Y at %l:%M%P"),
      should_charge: reservation.paid?,
    }
  end

  def extend_reservation
    reservation = Reservation.find(params[:id])
    # Without this, any authenticated member could extend ANY reservation by id
    # (Reservation.find is not owner/tenant-scoped) and trigger an off-session
    # charge against the victim owner. extend_reservation? = owner-or-staff and
    # not-in-the-past.
    authorize reservation, :extend_reservation?

    additional_duration = params[:duration].to_i

    result = Billing::Reservations::ExtendReservation.call(reservation: reservation, additional_duration: additional_duration, user: reservation.user)

    if result.success?
      flash[:notice] = "Reservation extended successfully."
      turbo_redirect(reservation_path(reservation), action: restore_if_possible)
    else
      flash[:error] = result.message
      turbo_redirect(reservation_path(reservation), action: "replace")
    end
  end

  def end_now
    find_reservation
    authorize @reservation, :end_now?

    if @reservation.end_now!
      flash[:notice] = "Reservation ended early successfully."
      turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
    else
      flash[:error] = "An error occurred while ending the reservation early."
      turbo_redirect(reservation_path(@reservation), action: "replace")
    end
  end

  def update_note
    find_reservation
    # Every sibling action authorizes; without this any authenticated member at
    # the location could edit another member's reservation note (find_reservation
    # is location-scoped, not owner-scoped). manage? = owner-or-staff.
    authorize @reservation, :manage?

    if @reservation.update(note: params[:reservation][:note])
      flash[:notice] = "Reservation note updated successfully."
      turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
    else
      flash[:error] = "An error occurred while update the reservation note."
      turbo_redirect(reservation_path(@reservation), action: "replace")
    end
  end

  # Day Office admin reassign (Task 12, ADR 0026): staff-only move of a live
  # hold to a different active room at its location (hidden rooms included —
  # decision #8). Redirects to the member's Day Passes admin page (Task 14)
  # rather than reservation_path — there's no dedicated show page for a hold.
  def reassign_room
    # Not find_reservation: that goes through Reservation's default scope,
    # which hides a cancelled hold behind a bare 404 before the service ever
    # gets a chance to run its own liveness check and give a clear flash
    # instead (mirrors the admin API's find_reservation, .unscoped for the
    # same reason).
    #
    # Tenant-scoped, not current_location-scoped (unlike this controller's
    # other actions): the Task 14 profile page lists every hold for a member
    # across ALL of the operator's locations, so an admin whose
    # current_location is site A must still be able to reassign a hold that
    # lives at site B.
    #
    # NOTE this is deliberately WIDER than the admin API's equivalent. PRs
    # #717/#718 shipped the cross-location tightening there: the API's
    # find_reservation/find_room/visible_reservations now confine
    # non-superadmins to allowed_location_ids (managed locations + home), so
    # the API's reassign_room 404s on a hold outside them. This web action
    # keeps operator-wide reach because the surface that calls it is the
    # member profile's all-locations hold list; the tradeoff is that a
    # location-scoped community manager can move a hold at a location they
    # do not manage (ReservationPolicy#reassign_room? is role-only, not
    # location-aware). Bringing the web surface to the API's boundary means
    # first deciding what the profile page should show for out-of-scope
    # locations — a follow-up, not a silent change here.
    #
    # Room.unscoped, wrapping BOTH lookups below: Room's own
    # acts_as_scopable(:operator, :location) default scope — populated for
    # the whole request by Operator::BaseController#set_resource_scopes —
    # silently narrows any Room-touching query (a join included, per
    # ActiveRecord's normal behavior of applying a joined model's default
    # scope) to the admin's current_location. Left in place, that would
    # undo the tenant-wide fix above: the join here would drop a hold at a
    # different location right back out, and the room lookup below would
    # fail to find a same-operator, different-location target room. Mirrors
    # Reservation#room's own Room.unscoped { super } override, same reason.
    @reservation = Room.unscoped do
      Reservation.unscoped.joins(:room).where(rooms: { operator_id: current_tenant.id }).find(params[:id])
    end
    authorize @reservation, :reassign_room?

    room = Room.unscoped { current_tenant.rooms.active.find_by(id: params[:room_id]) }
    result = DayOffices::ReassignRoom.call(hold: @reservation, room: room)

    if result.ok?
      flash[:notice] = result.moved? ? "Office hold moved to #{@reservation.reload.room.name}." : "Already in #{@reservation.room.name}."
    else
      flash[:error] = result.error
    end

    # Deterministic redirect to the member's Day Passes page — not
    # referrer_or_root — so the admin always lands somewhere that reflects
    # the outcome, regardless of which page the Reassign form was submitted
    # from. day_office_pass should always be present: the liveness guard
    # inside ReassignRoom.call already refuses anything that isn't a live Day
    # Office hold before this point. Fall back rather than raise if that
    # invariant is ever wrong.
    if @reservation.day_office_pass
      turbo_redirect(user_admin_day_passes_path(@reservation.day_office_pass.user))
    else
      turbo_redirect(referrer_or_root)
    end
  end

  def needs_billing
    date = Time.zone.parse(params[:date])
    should_charge = current_user.should_charge_for_reservation?(current_location, date)

    # Check day pass overage: if user is day pass holder and booking exceeds included time
    if !should_charge && params[:duration].present? && current_user.has_active_day_pass?(date.to_date)
      duration = params[:duration].to_i
      charge_info = current_user.day_pass_reservation_charge_info(current_location, date.to_date, duration)
      if charge_info && charge_info[:charge_type] == :partial_overage
        should_charge = true
      end
    end

    # Check subscription overage: if member's plan has meeting room limits
    if !should_charge && params[:duration].present?
      begin
        duration = params[:duration].to_i
        sub_info = current_user.subscription_reservation_charge_info(current_location, duration)
        if sub_info && sub_info[:charge_type] == :partial_overage
          should_charge = true
        end
      rescue => e
        Rails.logger.error("subscription_reservation_charge_info error in needs_billing: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
      end
    end

    has_billing = current_user.has_billing_for_location?(current_location)

    render json: { needs_billing: should_charge && !has_billing }
  end

  def daily_counts
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])

    reservations = Reservation.for_location_id(current_location.id).not_cancelled
                            .where(datetime_in: start_date.beginning_of_day..end_date.end_of_day)

    if params[:room_id].present?
      reservations = reservations.where(room_id: params[:room_id])
    end

    pg_timezone = ActiveSupport::TimeZone::MAPPING[current_location.time_zone]

    counts = reservations.group(
      "DATE(datetime_in AT TIME ZONE '#{pg_timezone}')"
    ).count

    formatted_counts = {}
    (start_date..end_date).each do |date|
      formatted_counts[date.strftime("%Y-%m-%d")] = counts[date] || 0
    end

    render json: formatted_counts
  end

  def daily_details
    date = Date.parse(params[:date])

    # Get reservations for the full day in location's timezone
    start_time = date.in_time_zone(current_location.time_zone).beginning_of_day
    end_time = date.in_time_zone(current_location.time_zone).end_of_day

    reservations = Reservation.for_location_id(current_location.id)
                            .not_cancelled
                            .includes(:room) # Eager load room to avoid N+1
                            .where(datetime_in: start_time..end_time)
                            .order(datetime_in: :asc)

    reservation_details = reservations.map do |reservation|
      {
        id: reservation.id,
        datetime_in: reservation.datetime_in.in_time_zone(current_location.time_zone).iso8601,
        minutes: reservation.minutes,
        room_name: reservation.room.name,
        room_id: reservation.room_id,
        user_name: reservation.user.name,
        note: reservation.note
      }
    end

    render json: reservation_details
  rescue ArgumentError => e
    render json: { error: "Invalid date format" }, status: :unprocessable_entity
  end

  private

  # Returns a Date from either a free-text `params[:day]` (e.g. "2026-05-21")
  # OR the Rails `date_select`-style `day(1i)`/`day(2i)`/`day(3i)` triple,
  # or `nil` if neither produces a valid date. Used by the operator
  # reservation creation flow (choose_time_post / choose_time) so blank
  # date submissions redirect back to the picker with a flash instead of
  # crashing in `Date.new(0, 0, 0)`.
  def parsed_day_param
    if params[:day].present?
      Date.parse(params[:day]) rescue nil
    else
      y = params["day(1i)"].to_i
      m = params["day(2i)"].to_i
      d = params["day(3i)"].to_i
      return nil if y.zero? || m.zero? || d.zero?
      Date.new(y, m, d) rescue nil
    end
  end

  def find_reservation(key = :id)
    @reservation = Reservation.for_location_id(current_location&.id).find(params[key])
  end

  def set_reserved_user
    if staff
      @user = User.for_space(current_tenant).find_by(id: params[:user_id]) || current_user
    else
      @user = current_user
    end
  end

  def staff
    return false unless current_user.present?
    current_user.admin_of_location?(current_location) || current_user.general_manager_of_location?(current_location) || current_user.community_manager_of_location?(current_location)
  end

  # Reserve Now — instant booking flow

  def reserve_now
    instant_book
  end

  def instant_book
    room = current_location&.rooms&.visible&.first
    render html: "INSTANT BOOK v2 - Room: #{room&.name || 'NIL'} | Location: #{current_location&.name || 'NIL'} | User: #{current_user&.id || 'NIL'} | Rooms count: #{current_location&.rooms&.visible&.count || 0}".html_safe, layout: false
  end

  def reserve_now_price
    room = current_location.rooms.find(params[:room_id])
    duration = params[:duration].to_i
    date = Time.zone.parse(params[:date])

    should_charge = current_user.should_charge_for_reservation?(current_location, date)
    hourly_price = room.hourly_rate_in_cents / 100.0
    total_price = hourly_price * (duration / 60.0)

    # Check subscription overage
    begin
      sub_info = current_user.subscription_reservation_charge_info(current_location, duration)
    rescue => e
      sub_info = nil
    end

    # Check day pass overage
    begin
      dp_info = current_user.day_pass_reservation_charge_info(current_location, date.to_date, duration)
    rescue => e
      dp_info = nil
    end

    included = !should_charge && room.hourly_rate_in_cents > 0
    if sub_info && sub_info[:charge_type] == :partial_overage
      included = false
      total_price = sub_info[:overage_amount_in_cents] / 100.0
    end
    if dp_info && dp_info[:charge_type] == :partial_overage
      included = false
      total_price = dp_info[:overage_amount_in_cents] / 100.0
    end

    render json: {
      should_charge: should_charge || (sub_info&.dig(:charge_type) == :partial_overage) || (dp_info&.dig(:charge_type) == :partial_overage),
      included: included,
      total_price: total_price,
      hourly_price: hourly_price,
      included_minutes_remaining: sub_info&.dig(:included_minutes_remaining) || dp_info&.dig(:included_minutes_remaining),
    }
  end

  private

  def compute_reserve_now_pricing
    @should_charge = current_user.should_charge_for_reservation?(current_location, @start_time.to_date)
    @hourly_price = @room.hourly_rate_in_cents / 100.0
    @total_price = @hourly_price * (@duration / 60.0)

    begin
      @subscription_charge_info = current_user.subscription_reservation_charge_info(current_location, @duration)
    rescue => e
      @subscription_charge_info = nil
    end

    begin
      @day_pass_charge_info = current_user.day_pass_reservation_charge_info(current_location, @start_time.to_date, @duration)
    rescue => e
      @day_pass_charge_info = nil
    end

    @included_in_plan = !@should_charge && @room.hourly_rate_in_cents > 0
    if @subscription_charge_info && @subscription_charge_info[:charge_type] == :partial_overage
      @included_in_plan = false
      @total_price = @subscription_charge_info[:overage_amount_in_cents] / 100.0
    end
    if @day_pass_charge_info && @day_pass_charge_info[:charge_type] == :partial_overage
      @included_in_plan = false
      @total_price = @day_pass_charge_info[:overage_amount_in_cents] / 100.0
    end

    @included_minutes_remaining = @subscription_charge_info&.dig(:included_minutes_remaining) || @day_pass_charge_info&.dig(:included_minutes_remaining)
  end

  public

  def create_reservation_params
    params.permit(:room_id, :date, :time, :duration, :day_or_night, :note, :attendee_count)
  end

  def reservation_params
    params.require(:reservation).permit(:room_id, :datetime_in, :hours)
  end

  def flatten_date_array(hash)
    %w(1 2 3).map { |e| hash["date(#{e}i)"].to_i }
  end

  def parse_time
    zone = ActiveSupport::TimeZone[@room.location.time_zone]
    @datetime_in = zone.local(@day.year, @day.month, @day.day, @hour.hour, @hour.min)
  end
end
