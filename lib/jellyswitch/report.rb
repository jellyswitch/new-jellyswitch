require "csv"

module Jellyswitch
  class Report
    include ApplicationHelper
    attr_accessor :operator, :location

    delegate :plans, :office_leases, :day_passes, :users, :square_footage, :name, :organizations, to: :delegate_target
    delegate :locations, to: :operator

    def initialize(operator, location = nil)
      @operator = operator
      @location = location
    end

    def delegate_target
      location || operator
    end

    def member_csv
      ::CSV.generate(headers: true) do |csv|
        csv << ["Name",
          "Account Creation Date",
          "Email",
          "Member of organization?",
          "Organization",
          "Membership",
          "Payment Method",
          "Stripe Customer ID"
        ]

        operator.users.originally_at_location(location).map do |user|
          subscription = user.subscriptions.active.first
          if subscription.present?
            subscription = subscription.pretty_name
          else
            subscription = "None"
          end

          csv << [user.name,
            short_date(user.created_at),
            user.email,
            boolean_to_yesno(user.member_of_organization?),
            user.organization_name,
            subscription,
            user.payment_method,
            user.stripe_customer_id_for_location(location)
          ]
        end
      end
    end

    def subscribed_members
      User.where(id: Subscription.where(plan: plans.individual.nonzero, active: true, subscribable_type: 'User').select(:subscribable_id))
    end

    def out_of_band_members
      users.members.where(out_of_band: true)
    end

    def active_members
      # Combine subscribed + out-of-band members via ID union
      subscribed_ids = Subscription.where(plan: plans.individual.nonzero, active: true, subscribable_type: 'User').select(:subscribable_id)
      oob_ids = out_of_band_members.select(:id)
      User.where(id: subscribed_ids).or(User.where(id: oob_ids))
    end

    def active_member_count
      active_members.count
    end

    def active_member_breakdown
      subscribed_count = subscribed_members.count
      oob_count = out_of_band_members.where.not(id: subscribed_members.select(:id)).count
      {
        subscribed: subscribed_count,
        out_of_band: oob_count,
        free: free_member_count
      }
    end

    def free_members
      User.where(id: Subscription.where(plan: plans.individual.free, active: true, subscribable_type: 'User').select(:subscribable_id))
    end

    def free_member_count
      free_members.count
    end

    def active_leases
      office_leases.active
    end

    def active_lease_count
      active_leases.count
    end

    def active_lease_members
      User.where(organization_id: office_leases.active.select(:organization_id)).distinct
    end

    def active_lease_member_count
      active_lease_members.count
    end

    def last_30_day_passes
      day_passes.last_30_days
    end

    def last_30_day_pass_count
      last_30_day_passes.count
    end

    def checkins_last_30_days
      scope = if location
        location.checkins
      else
        Checkin.where(location: locations)
      end

      scope.where(datetime_in: 30.days.ago..)
    end

    def checkins_last_30_days_count
      checkins_last_30_days.count
    end

    def all_members
      users.members.non_superadmins.order("name")
    end

    def all_member_count
      all_members.count
    end

    def organization_count
      organizations.count
    end

    def staff
      users.admins.non_superadmins
    end

    def staff_count
      staff.count
    end

    def membership_breakdown
      subscriptions = Subscription.for_operator(operator)
      subscriptions = subscriptions.for_location(location) if location
      subscriptions.where("plans.plan_type = ?", "individual").active
    end

    def membership_breakdown_count
      membership_breakdown.group("plans.name").count
    end

    def membership_breakdown_plan_count
      membership_breakdown.group(:plan).count
    end

    # Use Invoice.for_location which includes invoices with NULL location_id
    # (office leases created via webhook may not have location_id set)
    def location_invoices
      Invoice.for_location(location)
    end

    def this_month_revenue
      return 0 unless location
      invoice_rev = location_invoices.paid
        .where(due_date: Time.current.beginning_of_month..Time.current.end_of_month)
        .sum(:amount_due).to_f / 100.0
      lease_rev = lease_supplement_for_month(Date.today)
      invoice_rev + lease_rev
    end

    def revenue_by_month
      # All invoice revenue (memberships, day passes, and lease orgs that pay via Stripe)
      invoice_data = location_invoices.paid
        .where(due_date: 12.months.ago..)
        .group_by_month(:due_date).sum(:amount_due)

      # Normalize all keys to Date (beginning of month) and merge
      combined = Hash.new(0.0)
      invoice_data.each do |key, amt|
        combined[key.to_date.beginning_of_month] += amt.to_f / 100.0
      end

      # Add lease revenue only for orgs that DON'T have invoices that month
      start_month = 12.months.ago.to_date.beginning_of_month
      current_month = Date.today.beginning_of_month
      month = start_month
      while month <= current_month
        combined[month] += lease_supplement_for_month(month)
        month = month.next_month
      end

      combined.sort.to_h
    end

    def revenue_by_week
      location_invoices.paid.where(due_date: 6.months.ago..).group_by_week(:due_date).sum(:amount_due).transform_values do |amt|
        amt.to_f / 100.0
      end
    end

    def revenue_by_day
      location_invoices.paid.where(due_date: 3.months.ago..).group_by_day(:due_date).sum(:amount_due).transform_values do |amt|
        amt.to_f / 100.0
      end
    end

    def checkins_by_day
      target_locations = location ? [location] : locations
      target_locations.map do |loc|
        Struct.new(:label, :data).new(
          loc.name,
          loc.checkins.where(datetime_in: 90.days.ago..).group_by_day(:datetime_in).count
        )
      end
    end

    def checkin_revenue_by_day
      target_locations = location ? [location] : locations
      target_locations.map do |loc|
        Struct.new(:label, :data).new(
          loc.name,
          loc.checkins.where(datetime_in: 90.days.ago..).includes(:invoice).group_by_day(:datetime_in).sum("invoices.amount_due").transform_values {|v| v.to_f / 100.0}
        )
      end
    end

    # ── Lifetime Value (LTV) ──

    LtvResult = Struct.new(:product, :customers, :total_revenue, :average, :median, keyword_init: true)

    def ltv_summary
      {
        day_passes: day_pass_ltv,
        memberships: membership_ltv,
        office_leases: office_lease_ltv,
        meeting_rooms: meeting_room_ltv
      }
    end

    def ltv_for_timeframe(since: nil)
      {
        day_passes: day_pass_ltv(since: since),
        memberships: membership_ltv(since: since),
        office_leases: office_lease_ltv(since: since),
        meeting_rooms: meeting_room_ltv(since: since)
      }
    end

    def day_pass_ltv(since: nil)
      scope = day_passes.joins(:day_pass_type)
      scope = scope.where("day_passes.day >= ?", since) if since
      # Revenue per user: count of passes * price per pass type
      per_user = scope.group(:user_id).select(
        "user_id, SUM(day_pass_types.amount_in_cents) as total_cents"
      ).map { |r| r.total_cents.to_f / 100.0 }
      build_ltv_result("Day Passes", per_user)
    end

    def membership_ltv(since: nil)
      scope = location_invoices.paid.where(billable_type: "User")
      scope = scope.where("invoices.due_date >= ?", since) if since
      per_user = scope.group(:billable_id).sum(:amount_due).values.map { |v| v.to_f / 100.0 }
      build_ltv_result("Memberships", per_user)
    end

    def office_lease_ltv(since: nil)
      org_totals = Hash.new(0.0)

      office_leases.includes(subscription: :plan).find_each do |lease|
        plan = lease.subscription&.plan
        next unless plan

        effective_start = since ? [lease.start_date, since.to_date].max : lease.start_date
        effective_end = [lease.end_date, Date.today].min
        next if effective_start >= effective_end

        months_active = ((effective_end.year * 12 + effective_end.month) -
                         (effective_start.year * 12 + effective_start.month)).to_f

        interval_months = case plan.interval
                          when "monthly" then 1
                          when "quarterly" then 3
                          when "biannually" then 6
                          when "annually" then 12
                          else 1
                          end

        billing_periods = (months_active / interval_months).ceil
        billing_periods = [billing_periods, 1].max
        revenue = (plan.amount_in_cents * billing_periods) / 100.0

        org_totals[lease.organization_id] += revenue
      end

      build_ltv_result("Office Leases", org_totals.values)
    end

    def meeting_room_ltv(since: nil)
      target_locations = location ? [location] : locations
      room_ids = Room.where(location: target_locations, rentable: true).pluck(:id)
      scope = Reservation.unscoped.where(cancelled: false, paid: true, room_id: room_ids)
      scope = scope.where("datetime_in >= ?", since) if since
      # Calculate per-user revenue from room charges
      reservations_with_rooms = scope.includes(:room)
      user_totals = Hash.new(0.0)
      reservations_with_rooms.find_each do |res|
        next unless res.room
        charge = ((res.room.hourly_rate_in_cents / 60.0) * res.minutes).to_i
        user_totals[res.user_id] += charge.to_f / 100.0
      end
      build_ltv_result("Meeting Rooms", user_totals.values)
    end

    # ── Multi-Timeframe Trends ──

    TREND_PERIODS = { "30d" => 30, "90d" => 90, "1yr" => 365 }.freeze

    def trends_for(metric, current_value = nil)
      results = {}
      TREND_PERIODS.each do |label, days|
        prev_value = historical_value(metric, days)
        if prev_value && prev_value > 0
          change = ((current_value.to_f - prev_value) / prev_value * 100).round(1)
          results[label] = change
        end
      end
      results
    end

    def historical_value(metric, days_ago)
      case metric
      when :mrr
        # Approximate past MRR from invoice revenue for that month
        target_month = days_ago.days.ago.beginning_of_month
        location_invoices.paid
          .where(due_date: target_month..target_month.end_of_month)
          .sum(:amount_due).to_f / 100.0
      when :active_members
        # Count users who had active subs at that time
        Subscription.where(plan: plans.individual.nonzero, active: true)
          .where("subscriptions.created_at <= ?", days_ago.days.ago)
          .distinct.count(:subscribable_id)
      when :room_utilization
        room_utilization(days_ago)
      when :visits_per_member
        avg_visits_per_member_per_month(days_ago)
      when :churn
        churned_members_count(days_ago).to_f / [(active_member_count + churned_members_count(days_ago)), 1].max * 100
      else
        nil
      end
    rescue => e
      nil
    end

    # ── Actionable Insights ──

    def actionable_insights
      results = []

      # Inactive members → re-engagement
      inactive = inactive_member_count
      if inactive > 0
        results << {
          text: "#{inactive} members haven't visited in 30+ days.",
          action: "Send re-engagement campaign",
          path: :campaigns_path,
          urgency: inactive > 10 ? :high : :medium
        }
      end

      # Churn alert
      churn = churn_rate
      if churn > 5
        results << {
          text: "Churn rate is #{churn}% — above the 3-5% industry average.",
          action: "Review cancelled members",
          path: :total_members_reports_path,
          urgency: :high
        }
      end

      # Room demand misses
      if location
        misses = RoomDemandMiss.for_location(location).where("missed_at > ?", 30.days.ago).count
        if misses > 5
          results << {
            text: "#{misses} members couldn't find a room this month.",
            action: "View room demand report",
            path: :room_demand_reports_path,
            urgency: misses > 20 ? :high : :medium
          }
        end
      end

      # Expiring leases
      if location
        expiring = office_leases.where("end_date BETWEEN ? AND ?", Date.today, 60.days.from_now).count
        if expiring > 0
          results << {
            text: "#{expiring} lease#{expiring > 1 ? 's' : ''} expire#{expiring == 1 ? 's' : ''} in the next 60 days.",
            action: "View active leases",
            path: :active_leases_reports_path,
            urgency: :high
          }
        end
      end

      # Day pass conversion opportunity
      conv = day_pass_conversion_rate
      if conv < 5 && last_30_day_pass_count > 5
        results << {
          text: "Only #{conv}% of day pass buyers become members. #{last_30_day_pass_count} day passes sold in 30 days.",
          action: "Create a nurture campaign for day passers",
          path: :new_campaign_path,
          urgency: :medium
        }
      end

      # Low utilization
      util = room_utilization
      if util < 20 && util > 0
        results << {
          text: "Room utilization is only #{util}%. Rooms are underused.",
          action: "Consider promotions or events to drive bookings",
          path: :rooms_path,
          urgency: :low
        }
      end

      # Revenue forecast
      projected = mrr
      if projected > 0
        results << {
          text: "Projected next month revenue: #{ActionController::Base.helpers.number_to_currency(projected, precision: 0)} based on current subscriptions + leases.",
          action: nil,
          urgency: :info
        }
      end

      results.sort_by { |r| { high: 0, medium: 1, low: 2, info: 3 }[r[:urgency]] }.first(6)
    rescue => e
      Rails.logger.warn("actionable_insights error: #{e.message}")
      []
    end

    # ── Analytics Dashboard Metrics ──

    def mrr(product_filter: "all")
      return 0 unless location
      total = 0.0

      # Membership MRR
      if %w[all memberships].include?(product_filter)
        Subscription.where(plan: plans.individual.nonzero, active: true).includes(:plan).find_each do |sub|
          total += normalize_to_monthly(sub.plan)
        end
      end

      # Office lease MRR
      if %w[all offices].include?(product_filter)
        office_leases.active.includes(subscription: :plan).each do |lease|
          total += normalize_to_monthly(lease.subscription&.plan) if lease.subscription&.plan
        end
        # Out-of-band leases (paid by check, no Stripe subscription with plan amount)
        office_leases.active.includes(subscription: :plan).each do |lease|
          plan = lease.subscription&.plan
          next if plan && plan.amount_in_cents > 0
          # Use the office's monthly rate if the plan has no amount
          total += (lease.office&.monthly_rate_in_cents || 0).to_f / 100.0 if lease.office.respond_to?(:monthly_rate_in_cents)
        end
      end

      # Day pass MRR (average monthly day pass revenue)
      if %w[all day_passes].include?(product_filter)
        dp_rev = day_passes.joins(:day_pass_type)
          .where("day_passes.created_at > ?", 3.months.ago)
          .sum("day_pass_types.amount_in_cents").to_f / 100.0
        total += dp_rev / 3.0 # Average over 3 months
      end

      # Meeting room MRR (average monthly room revenue)
      if %w[all meeting_rooms].include?(product_filter)
        room_ids = location.rooms.rentable.pluck(:id)
        if room_ids.any?
          room_rev = Reservation.where(room_id: room_ids, cancelled: false, paid: true)
            .where("datetime_in > ?", 3.months.ago)
            .joins(:room)
            .sum("(rooms.hourly_rate_in_cents / 60.0) * reservations.minutes").to_f / 100.0
          total += room_rev / 3.0
        end
      end

      total.round(0)
    end

    def mrr_by_month(months = 12, product_filter: "all")
      result = {}
      months.times do |i|
        date = i.months.ago.beginning_of_month
        month_end = date.end_of_month
        label = date.strftime("%b %Y")
        total = 0.0

        if %w[all memberships].include?(product_filter)
          total += Subscription.where(plan: plans.individual.nonzero, active: true)
            .where("subscriptions.created_at <= ?", month_end)
            .includes(:plan)
            .sum { |s| normalize_to_monthly(s.plan) }
        end

        if %w[all offices].include?(product_filter)
          office_leases.where("start_date <= ? AND end_date >= ?", month_end, date)
            .includes(subscription: :plan).each do |lease|
              total += normalize_to_monthly(lease.subscription&.plan) if lease.subscription&.plan
            end
        end

        # Day pass + meeting room: use actual revenue for that month
        if %w[all day_passes].include?(product_filter)
          total += day_passes.joins(:day_pass_type)
            .where(created_at: date..month_end)
            .sum("day_pass_types.amount_in_cents").to_f / 100.0
        end

        if %w[all meeting_rooms].include?(product_filter)
          room_ids = location.rooms.rentable.pluck(:id)
          if room_ids.any?
            total += Reservation.where(room_id: room_ids, cancelled: false, paid: true)
              .where(datetime_in: date..month_end)
              .joins(:room)
              .sum("(rooms.hourly_rate_in_cents / 60.0) * reservations.minutes").to_f / 100.0
          end
        end

        result[label] = total.round(0)
      end
      result.reverse_each.to_h
    end

    def churn_rate(period_days = 30)
      return 0 unless location
      churned = churned_members_count(period_days)
      # Members at start of period ≈ current active + those who cancelled
      starting_members = active_member_count + churned
      return 0 if starting_members == 0

      months = [period_days / 30.0, 1].max
      # Monthly churn rate: (cancellations per month) / starting members
      monthly_cancellations = churned.to_f / months
      (monthly_cancellations / starting_members * 100).round(1)
    end

    def churned_members_count(period_days = 30)
      # Use actual subscription data: individual subscriptions that became inactive in the period
      Subscription.where(plan: plans.individual.nonzero, active: false)
        .where("subscriptions.updated_at > ?", period_days.days.ago)
        .where(subscribable_type: "User")
        .distinct.count(:subscribable_id)
    end

    def room_utilization(period_days = 30)
      return 0 unless location
      rooms = location.rooms.visible
      return 0 if rooms.count == 0

      business_hours_per_day = 10.0 # 8am-6pm
      business_days = (period_days * 5.0 / 7).round # approximate weekdays
      available_hours = rooms.count * business_hours_per_day * business_days

      booked_minutes = Reservation.where(room: rooms, cancelled: false)
        .where("datetime_in > ?", period_days.days.ago)
        .where("EXTRACT(HOUR FROM datetime_in) >= 8 AND EXTRACT(HOUR FROM datetime_in) < 18")
        .sum(:minutes)

      return 0 if available_hours == 0
      ((booked_minutes / 60.0) / available_hours * 100).round(1)
    end

    def avg_daily_visitors(period_days = 30)
      return 0 unless location
      visitor_days = DoorPunch.where(door: location.doors)
        .where("created_at > ?", period_days.days.ago)
        .count("DISTINCT (DATE(created_at), user_id)")
      days = [period_days, 1].max
      (visitor_days.to_f / days).round(1)
    rescue => e
      Rails.logger.warn("avg_daily_visitors error: #{e.message}")
      0
    end

    def avg_visits_per_member_per_month(period_days = 30)
      return 0 unless location
      member_count = active_member_count + active_lease_member_count
      return 0 if member_count == 0

      total_visit_days = DoorPunch.where(door: location.doors)
        .where("created_at > ?", period_days.days.ago)
        .count("DISTINCT (DATE(created_at), user_id)")

      months = [period_days / 30.0, 1].max
      ((total_visit_days.to_f / member_count) / months).round(1)
    rescue => e
      Rails.logger.warn("avg_visits_per_member_per_month error: #{e.message}")
      0
    end

    def new_members_count(period_days = 30)
      # Only count users who got a subscription (actual members, not day passers)
      Subscription.joins(:plan)
        .where(plans: { operator_id: operator.id })
        .where("subscriptions.created_at > ?", period_days.days.ago)
        .where(subscribable_type: "User")
        .distinct.count(:subscribable_id)
    end

    def new_signups_count(period_days = 30)
      User.for_space(operator)
        .originally_at_location(location)
        .approved.visible
        .where("users.created_at > ?", period_days.days.ago)
        .count
    end

    def net_member_growth(period_days = 30)
      new_members_count(period_days) - churned_members_count(period_days)
    end

    def revenue_per_member
      member_count = active_member_count
      return 0 if member_count == 0
      (this_month_revenue / member_count).round(2)
    end

    def average_member_tenure
      members = active_members
      return 0 if members.count == 0
      total_months = members.sum { |u| ((Time.current - u.created_at) / 1.month).round(1) }
      (total_months / members.count).round(1)
    end

    def day_pass_conversion_rate
      return 0 unless location
      dp_users = day_passes.distinct.count(:user_id)
      return 0 if dp_users == 0

      converted = day_passes.joins("INNER JOIN subscriptions ON subscriptions.subscribable_id = day_passes.user_id AND subscriptions.subscribable_type = 'User'")
        .where("subscriptions.created_at > day_passes.created_at")
        .distinct.count("day_passes.user_id")

      (converted.to_f / dp_users * 100).round(1)
    end

    def revenue_by_product(period_days = 365)
      result = {}
      cutoff = period_days.days.ago

      # Membership revenue
      result["Memberships"] = location_invoices.paid
        .where(billable_type: "User")
        .where("due_date > ?", cutoff)
        .sum(:amount_due).to_f / 100.0

      # Day pass revenue
      result["Day Passes"] = day_passes.joins(:day_pass_type)
        .where("day_passes.created_at > ?", cutoff)
        .sum("day_pass_types.amount_in_cents").to_f / 100.0

      # Meeting room revenue
      room_ids = (location&.rooms&.rentable&.pluck(:id) || [])
      if room_ids.any?
        result["Meeting Rooms"] = Reservation.where(room_id: room_ids, cancelled: false, paid: true)
          .where("datetime_in > ?", cutoff)
          .joins(:room)
          .sum("(rooms.hourly_rate_in_cents / 60.0) * reservations.minutes").to_f / 100.0
      end

      # Office lease revenue
      result["Office Leases"] = location_invoices.paid
        .where(billable_type: "Organization")
        .where("due_date > ?", cutoff)
        .sum(:amount_due).to_f / 100.0

      result.reject { |_, v| v <= 0 }
    end

    def peak_hours_heatmap(period_days = 30)
      return {} unless location
      punches = DoorPunch.where(door: location.doors)
        .where("created_at > ?", period_days.days.ago)

      heatmap = {}
      %w[Mon Tue Wed Thu Fri Sat Sun].each { |d| heatmap[d] = {} }

      punches.find_each do |punch|
        day = punch.created_at.strftime("%a")
        hour = punch.created_at.hour
        next if hour < 8 || hour >= 18
        heatmap[day] ||= {}
        heatmap[day][hour] ||= 0
        heatmap[day][hour] += 1
      end

      heatmap
    end

    # ── Seasonal Intelligence ──

    def yoy_change(current_value, metric_method)
      last_year_value = calculate_last_year(metric_method)
      return nil if last_year_value.nil? || last_year_value == 0
      ((current_value - last_year_value).to_f / last_year_value * 100).round(1)
    end

    def insights
      results = []
      mom_mrr = mrr_mom_change
      yoy_mrr = yoy_change(mrr, :mrr)

      if mom_mrr && mom_mrr < 0 && yoy_mrr && yoy_mrr >= 0
        results << "MRR is down #{mom_mrr.abs}% from last month, but up #{yoy_mrr}% vs #{Date.today.prev_year.strftime('%B %Y')} — seasonal pattern typical for #{Date.today.strftime('%B')}."
      elsif mom_mrr && mom_mrr > 0
        results << "MRR is up #{mom_mrr}% from last month."
      end

      if avg_daily_visitors > 0
        busiest = peak_busiest_day
        results << "Your busiest day this month was #{busiest[:day]} (#{busiest[:count]} door punches)." if busiest
      end

      inactive_count = inactive_member_count
      results << "#{inactive_count} members haven't visited in 30+ days." if inactive_count > 0

      conv = day_pass_conversion_rate
      results << "#{conv}% of day pass buyers eventually became members." if conv > 0

      util = room_utilization
      results << "Room utilization is at #{util}% of available hours." if util > 0

      results.first(5)
    end

    def mrr_mom_change
      current = mrr
      # Rough last month MRR from the trend
      last_month_invoices = location_invoices.paid
        .where(due_date: 1.month.ago.beginning_of_month..1.month.ago.end_of_month)
        .sum(:amount_due).to_f / 100.0
      return nil if last_month_invoices == 0
      ((current - last_month_invoices) / last_month_invoices * 100).round(1)
    end

    def inactive_member_count
      return 0 unless location
      cutoff = 30.days.ago

      active_ids = active_members.pluck(:id)
      return 0 if active_ids.empty?

      door_active_ids = DoorPunch.where(user_id: active_ids)
        .where("created_at > ?", cutoff).distinct.pluck(:user_id)
      reservation_active_ids = Reservation.where(user_id: active_ids)
        .where("created_at > ?", cutoff).distinct.pluck(:user_id)

      visited_ids = (door_active_ids + reservation_active_ids).uniq
      active_ids.count - visited_ids.count
    end

    def peak_busiest_day(period_days = 30)
      return nil unless location
      counts = DoorPunch.where(door: location.doors)
        .where("created_at > ?", period_days.days.ago)
        .group("DATE(created_at)")
        .count
      return nil if counts.empty?
      busiest = counts.max_by { |_, v| v }
      { day: busiest[0].strftime("%A, %B %e"), count: busiest[1] }
    end

    private

    def normalize_to_monthly(plan)
      return 0.0 unless plan
      amount = plan.amount_in_cents.to_f / 100.0
      case plan.interval
      when "monthly" then amount
      when "quarterly" then amount / 3.0
      when "biannually" then amount / 6.0
      when "annually" then amount / 12.0
      else amount
      end
    end

    def calculate_last_year(metric_method)
      nil # Would require historical data snapshots; placeholder for now
    end

    def build_ltv_result(product, values)
      values = values.reject { |v| v <= 0 }
      total = values.sum
      avg = values.any? ? total / values.size : 0
      med = median(values)
      LtvResult.new(product: product, customers: values.size, total_revenue: total, average: avg, median: med)
    end

    def median(values)
      return 0 if values.empty?
      sorted = values.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    # Add lease revenue only for orgs that don't already have invoices that month.
    # Orgs paying via Stripe already show up in invoice revenue; this fills in
    # out-of-band (check) payers so all lease revenue is accounted for.
    def lease_supplement_for_month(date)
      month_start = date.to_date.beginning_of_month
      month_end = date.to_date.end_of_month

      # Find org IDs that already have invoices this month
      month_invoices = location_invoices.paid
        .where(due_date: month_start.beginning_of_day..month_end.end_of_day)
      orgs_with_invoices = Set.new

      # Orgs billed directly as Organization
      orgs_with_invoices.merge(month_invoices.where(billable_type: "Organization").pluck(:billable_id))

      # Orgs whose billing contact or owner has User invoices
      lease_org_ids = office_leases.where("start_date <= ? AND end_date >= ?", month_end, month_start)
                                   .pluck(:organization_id).uniq
      if lease_org_ids.any?
        contact_map = Organization.where(id: lease_org_ids)
                                  .pluck(:id, :billing_contact_id, :owner_id)
        contact_map.each do |org_id, contact_id, owner_id|
          user_ids = [contact_id, owner_id].compact
          next if user_ids.empty?
          if month_invoices.where(billable_type: "User", billable_id: user_ids).exists?
            orgs_with_invoices << org_id
          end
        end
      end

      # Only add revenue for orgs WITHOUT invoices
      total = 0.0
      office_leases.includes(subscription: :plan).each do |lease|
        plan = lease.subscription&.plan
        next unless plan
        next if lease.end_date < month_start || lease.start_date > month_end
        next if orgs_with_invoices.include?(lease.organization_id)

        monthly_amount = case plan.interval
                         when "monthly" then plan.amount_in_cents
                         when "quarterly" then plan.amount_in_cents / 3.0
                         when "biannually" then plan.amount_in_cents / 6.0
                         when "annually" then plan.amount_in_cents / 12.0
                         else plan.amount_in_cents
                         end

        total += monthly_amount / 100.0
      end

      total
    end
  end
end