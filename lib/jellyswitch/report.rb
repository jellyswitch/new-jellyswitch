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
      # Exclude archived and unapproved users
      subscribed_ids = Subscription.where(plan: plans.individual.nonzero, active: true, subscribable_type: 'User').select(:subscribable_id)
      oob_ids = out_of_band_members.select(:id)
      User.where(id: subscribed_ids).or(User.where(id: oob_ids)).visible.approved
    end

    def active_member_count
      active_members.count
    end

    # Comprehensive active membership: paying individuals + out-of-band +
    # members under organizations with active office leases. The dashboard
    # headline ("Active Members") should reflect this total — the historical
    # active_member_count is intentionally narrower (paying-only) and several
    # callers (weekly_update, operators_table, avg_visits_per_member) rely on
    # the split, so keep it and add this as a sibling.
    def total_active_members
      subscribed_ids = Subscription.where(plan: plans.individual.nonzero, active: true, subscribable_type: 'User').select(:subscribable_id)
      oob_ids = out_of_band_members.select(:id)
      lease_member_ids = active_lease_members.select(:id)
      User.where(id: subscribed_ids).or(User.where(id: oob_ids)).or(User.where(id: lease_member_ids)).visible.approved
    end

    def total_active_member_count
      total_active_members.count
    end

    def active_member_breakdown
      subscribed_count = subscribed_members.count
      oob_count = out_of_band_members.where.not(id: subscribed_members.select(:id)).count
      lease_count = active_lease_member_count
      {
        subscribed: subscribed_count,
        out_of_band: oob_count,
        on_lease: lease_count,
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
      # Lease members come in two shapes: users under an organization holding
      # an active office lease, and users who hold a lease-plan subscription
      # directly (a solo office tenant entered as a personal subscription —
      # Tahoe Longhouse, 2026-07-20). The direct shape was invisible to every
      # membership rollup: not individual-plan subscribed, and no organization
      # to ride in on.
      direct_leaseholder_ids = Subscription.where(plan: plans.lease, active: true, subscribable_type: 'User').select(:subscribable_id)
      User.where(organization_id: office_leases.active.select(:organization_id))
          .or(User.where(id: direct_leaseholder_ids))
          .distinct
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

    def day_pass_count(period_days = 30, range: nil)
      range, _days = resolve_period(period_days, range)
      # Bounded on both ends: `day` is a date and bundle days can be scheduled
      # in advance, so an open-ended window would count future passes today.
      day_passes.where(day: range.begin.to_date..range.end.to_date).count
    end

    def checkin_count(period_days = 30, range: nil)
      range, _days = resolve_period(period_days, range)
      scope = location ? location.checkins : Checkin.where(location: locations)
      scope.where(datetime_in: range).count
    end

    # Comprehensive period revenue — mirrors revenue_by_month semantics so the
    # mobile REVENUE tile matches the web dashboard chart. A plain
    # Invoice.sum(:amount_paid) misses out-of-band office-lease checks that the
    # operator records outside the invoice flow; lease_supplement_for_month
    # fills those in.
    def revenue_for_period(period_days = 30, range: nil)
      return 0 unless location
      range, _days = resolve_period(period_days, range)
      period_start = range.begin.to_date
      period_end = range.end.to_date

      invoice_rev = paid_invoices_in(period_start.beginning_of_day..period_end.end_of_day)
        .sum(:amount_due).to_f / 100.0

      (invoice_rev + lease_supplement_for_window(range)).round
    end

    # Average monthly revenue across the period — actual money (paid invoices
    # + out-of-band lease checks via revenue_by_month), averaged over the
    # window's COMPLETE months. The current partial month is excluded: four
    # days into July it would drag a 12-month average down for no reason.
    # Capped at 24 months so "All Time" doesn't blow the Heroku 30s timeout.
    #
    # This tile used to average mrr_by_month's synthetic snapshots, which
    # never look at invoices and undercounted by ~12% (survivorship on
    # cancelled subs + list prices instead of amounts actually paid). The
    # operator reads this as "revenue ÷ months" — make it exactly that.
    # The recurring run-rate is still available as #mrr.
    AVG_MRR_MAX_MONTHS = 24
    def avg_monthly_revenue(period_days = 30)
      months = [(period_days / 30.0).round, AVG_MRR_MAX_MONTHS].min
      months = [months, 1].max
      by_month = revenue_by_month(months + 1) rescue {}
      complete = by_month.reject { |m, _| m == Date.today.beginning_of_month }
      return this_month_revenue.round if complete.empty?
      (complete.values.sum / complete.size).round
    end
    alias avg_mrr avg_monthly_revenue

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

    # Revenue is recognized on COALESCE(due_date, date). Stripe only sets
    # due_date on emailed (send_invoice) invoices — auto-charged card
    # invoices carry due_date = NULL, so anything keyed on due_date alone
    # silently drops most card revenue. `date` (invoice creation/charge
    # time) is the fallback.
    EFFECTIVE_DATE_SQL = "COALESCE(invoices.due_date, invoices.date)".freeze

    def paid_invoices_in(range)
      location_invoices.paid
        .where("#{EFFECTIVE_DATE_SQL} BETWEEN ? AND ?", range.begin, range.end)
    end

    def this_month_revenue
      return 0 unless location
      invoice_rev = paid_invoices_in(Time.current.beginning_of_month..Time.current.end_of_month)
        .sum(:amount_due).to_f / 100.0
      lease_rev = lease_supplement_for_month(Date.today)
      invoice_rev + lease_rev
    end

    def revenue_by_month(months = 12)
      # Exactly `months` full calendar months including the current one — a
      # mid-month window start would show a misleading partial first month.
      # One sum per month (instead of group_by_month) so the COALESCE
      # effective-date key matches revenue_for_period exactly.
      start_month = (months - 1).months.ago.to_date.beginning_of_month
      current_month = Date.today.beginning_of_month

      combined = {}
      month = start_month
      while month <= current_month
        invoice_rev = paid_invoices_in(month.beginning_of_day..month.end_of_month.end_of_day)
          .sum(:amount_due).to_f / 100.0
        # Lease revenue only for orgs that DON'T have invoices that month
        combined[month] = invoice_rev + lease_supplement_for_month(month)
        month = month.next_month
      end

      combined
    end

    def revenue_by_week
      paid_invoices_in(6.months.ago..Time.current)
        .group_by_week(Arel.sql(EFFECTIVE_DATE_SQL)).sum(:amount_due).transform_values do |amt|
        amt.to_f / 100.0
      end
    end

    def revenue_by_day
      paid_invoices_in(3.months.ago..Time.current)
        .group_by_day(Arel.sql(EFFECTIVE_DATE_SQL)).sum(:amount_due).transform_values do |amt|
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
      scope = scope.where("#{EFFECTIVE_DATE_SQL} >= ?", since) if since
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
        paid_invoices_in(target_month..target_month.end_of_month)
          .sum(:amount_due).to_f / 100.0
      when :active_members
        # Approximate "active members as of days_ago" using the same three
        # buckets the headline now counts: subscriptions + OOB + office-lease
        # members. Both the historical query and the current value must
        # include all three or the trend percentage compares apples to
        # oranges. This is an approximation — cancelled subs and ended
        # leases aren't perfectly reconstructed, so a churn-heavy month
        # will undercount historical and overstate growth.
        cutoff = days_ago.days.ago
        sub_user_ids = Subscription.where(plan: plans.individual.nonzero, subscribable_type: 'User')
          .where("subscriptions.created_at <= ?", cutoff)
          .where("subscriptions.active = ? OR subscriptions.updated_at > ?", true, cutoff)
          .select(:subscribable_id)
        oob_user_ids = out_of_band_members.where("users.created_at <= ?", cutoff).select(:id)
        lease_org_ids = office_leases.where("start_date <= ?", cutoff)
          .where("end_date IS NULL OR end_date >= ?", cutoff)
          .select(:organization_id)
        lease_user_ids = User.where(organization_id: lease_org_ids)
          .where("users.created_at <= ?", cutoff).select(:id)
        User.where(id: sub_user_ids)
          .or(User.where(id: oob_user_ids))
          .or(User.where(id: lease_user_ids))
          .visible.approved.count
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
          action: "View inactive members",
          path: :inactive_members_reports_path,
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

      # Revenue forecast — contracted recurring plus history-driven
      # day-pass and room estimates (recent baseline × the month's
      # historical index), not a trailing average that lags seasonal
      # locations by a quarter.
      projected = projected_next_month_revenue
      if projected > 0
        results << {
          text: "Projected #{Date.current.next_month.strftime('%B')} revenue: #{ActionController::Base.helpers.number_to_currency(projected, precision: 0)} — subscriptions + leases + day-pass and room estimates from your history.",
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

      # Day pass MRR (average monthly day pass revenue). Purchased only —
      # a complimentary pass's list price isn't revenue.
      if %w[all day_passes].include?(product_filter)
        dp_rev = day_passes.purchased.joins(:day_pass_type)
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

    # ── History-driven forecasting ──
    #
    # Forecast = recent baseline × the target month's historical index.
    # The index measures how that calendar month has historically compared
    # to its surrounding year at THIS location, shrunk toward 1.0 by sample
    # count — so a tourist-town location (CT: July runs several times an
    # average month) gets its peaks, while a location with no real
    # seasonality (Choose Folsom) converges on its plain recent average.
    # No location-specific rules: the data decides how seasonal to be.

    # Actual purchased day-pass revenue for a calendar month. Bounded at
    # today — bundle days can be scheduled into future months — and
    # excludes complimentary passes (their list price isn't revenue).
    # Memoized per instance: the forecaster samples many months.
    def day_pass_revenue_for_month(month)
      month_start = month.to_date.beginning_of_month
      @day_pass_month_cache ||= {}
      @day_pass_month_cache[month_start] ||= begin
        if month_start > Date.current
          0.0
        else
          month_end = [month_start.end_of_month, Date.current].min
          purchased_day_pass_revenue(month_start..month_end)
        end
      end
    end

    def day_pass_forecast(month = Date.current.next_month)
      forecast_from_history(
        month,
        revenue_for_month: method(:day_pass_revenue_for_month),
        first_month: day_passes.purchased.minimum(:day)&.beginning_of_month,
      )
    end

    # Paid meeting-room revenue for a calendar month (same pricing basis as
    # the MRR room component), bounded at today.
    def room_revenue_for_month(month)
      return 0.0 unless location
      month_start = month.to_date.beginning_of_month
      @room_month_cache ||= {}
      @room_month_cache[month_start] ||= begin
        if month_start > Date.current
          0.0
        else
          room_ids = location.rooms.rentable.pluck(:id)
          if room_ids.empty?
            0.0
          else
            month_end = [month_start.end_of_month.end_of_day, Time.current].min
            Reservation.where(room_id: room_ids, cancelled: false, paid: true)
              .where(datetime_in: month_start.beginning_of_day..month_end)
              .joins(:room)
              .sum("(rooms.hourly_rate_in_cents / 60.0) * reservations.minutes").to_f / 100.0
          end
        end
      end
    end

    def room_forecast(month = Date.current.next_month)
      return 0 unless location
      first = Reservation.where(room_id: location.rooms.rentable.select(:id), cancelled: false, paid: true)
        .minimum(:datetime_in)&.to_date&.beginning_of_month
      forecast_from_history(month, revenue_for_month: method(:room_revenue_for_month), first_month: first)
    end

    # Next month's expected revenue: contracted recurring (memberships +
    # leases) at today's book, plus history-driven day-pass and room
    # estimates.
    def projected_next_month_revenue
      return 0 unless location
      contracted = mrr(product_filter: "memberships") + mrr(product_filter: "offices")
      (contracted + day_pass_forecast + room_forecast).round
    end

    # How the CURRENT month is tracking: actuals so far plus the expected
    # remainder. Usage products (day passes, rooms) get the rest of their
    # history-driven monthly estimate at a uniform pace; recurring gets the
    # not-yet-billed portion of the contracted book (anniversary billing
    # lands all month), floored at zero so a big early payment — an annual
    # payer, say — raises the forecast instead of going negative.
    def current_month_forecast
      return 0 unless location
      today = Date.current
      month_start = today.beginning_of_month
      days_in_month = today.end_of_month.day
      frac_remaining = (days_in_month - today.day).to_f / days_in_month

      buckets = revenue_by_product(range: month_start..today)
      mtd_total = buckets.values.sum

      dp_remaining = day_pass_forecast(month_start) * frac_remaining
      room_remaining = room_forecast(month_start) * frac_remaining

      contracted = mrr(product_filter: "memberships") + mrr(product_filter: "offices")
      recurring_mtd = buckets.fetch("Memberships", 0.0) + buckets.fetch("Office Leases", 0.0)
      recurring_remaining = [contracted - recurring_mtd, 0].max

      (mtd_total + dp_remaining + room_remaining + recurring_remaining).round
    end

    def mrr_by_month(months = 12, product_filter: "all")
      # Memoize per Report instance — the dashboard renders the MRR chart AND
      # the avg_mrr tile in the same request and both call this with similar
      # args. Without the cache, "All Time" timed out at >30s on Heroku.
      @mrr_by_month_cache ||= {}
      cache_key = [months, product_filter]
      return @mrr_by_month_cache[cache_key] if @mrr_by_month_cache.key?(cache_key)

      result = {}
      months.times do |i|
        date = i.months.ago.beginning_of_month
        month_end = date.end_of_month
        label = date.strftime("%b %Y")
        total = 0.0

        if %w[all memberships].include?(product_filter)
          # Subs that existed by month end and were still active during the
          # month. Filtering on active-today (as this used to) has
          # survivorship bias: every since-cancelled sub vanished from
          # history. updated_at approximates the cancellation time — the
          # same proxy churn uses.
          total += Subscription.where(plan: plans.individual.nonzero)
            .where("subscriptions.created_at <= ?", month_end)
            .where("subscriptions.active = ? OR subscriptions.updated_at >= ?", true, date)
            .includes(:plan)
            .sum { |s| normalize_to_monthly(s.plan) }
        end

        if %w[all offices].include?(product_filter)
          office_leases.where("start_date <= ? AND end_date >= ?", month_end, date)
            .includes(:office, subscription: :plan).each do |lease|
              plan = lease.subscription&.plan
              if plan && plan.amount_in_cents > 0
                total += normalize_to_monthly(plan)
              elsif lease.office.respond_to?(:monthly_rate_in_cents)
                # Out-of-band leases with no priced plan — same fallback #mrr
                # uses; this chart previously dropped them entirely.
                total += (lease.office&.monthly_rate_in_cents || 0).to_f / 100.0
              end
            end
        end

        # Day pass + meeting room: use actual revenue for that month
        if %w[all day_passes].include?(product_filter)
          total += day_passes.purchased.joins(:day_pass_type)
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
      @mrr_by_month_cache[cache_key] = result.reverse_each.to_h
    end

    def churn_rate(period_days = 30, range: nil)
      return 0 unless location
      range, days = resolve_period(period_days, range)
      churned = churned_members_count(range: range)
      # Members at start of period ≈ current active + those who cancelled
      starting_members = active_member_count + churned
      return 0 if starting_members == 0

      months = [days / 30.0, 1].max
      # Monthly churn rate: (cancellations per month) / starting members
      monthly_cancellations = churned.to_f / months
      (monthly_cancellations / starting_members * 100).round(1)
    end

    def churned_members_count(period_days = 30, range: nil)
      range, _days = resolve_period(period_days, range)
      # Use actual subscription data: individual subscriptions that became
      # inactive in the period. Users who still hold an active paid individual
      # subscription merely switched plans — they didn't churn.
      still_subscribed = Subscription.where(
        plan: plans.individual.nonzero, active: true, subscribable_type: "User",
      ).select(:subscribable_id)
      Subscription.where(plan: plans.individual.nonzero, active: false)
        .where(updated_at: range)
        .where(subscribable_type: "User")
        .where.not(subscribable_id: still_subscribed)
        .distinct.count(:subscribable_id)
    end

    def room_utilization(period_days = 30, range: nil)
      return 0 unless location
      rooms = location.rooms.visible
      return 0 if rooms.count == 0

      range, days = resolve_period(period_days, range)

      business_hours_per_day = 10.0 # 8am-6pm local
      business_days = (days * 5.0 / 7).round # approximate weekdays
      available_hours = rooms.count * business_hours_per_day * business_days
      return 0 if available_hours == 0

      # datetime_in is timestamptz; EXTRACT on the raw column yields UTC hours,
      # which shifted the 8am-6pm business window to ~1-11am Pacific and
      # silently dropped every afternoon booking. Convert to the location's
      # wall clock, and count weekdays only to match the denominator.
      tz = ActiveSupport::TimeZone[location.time_zone.presence || "UTC"].tzinfo.name
      local = "(datetime_in AT TIME ZONE ?)"
      booked_minutes = Reservation.where(room: rooms, cancelled: false)
        .where(datetime_in: range)
        .where("EXTRACT(HOUR FROM #{local}) >= 8 AND EXTRACT(HOUR FROM #{local}) < 18", tz, tz)
        .where("EXTRACT(ISODOW FROM #{local}) <= 5", tz)
        .sum(:minutes)

      ((booked_minutes / 60.0) / available_hours * 100).round(1)
    end

    def avg_daily_visitors(period_days = 30, range: nil)
      return 0 unless location
      range, days = resolve_period(period_days, range)
      visitor_days = DoorPunch.where(door: location.doors)
        .where(created_at: range)
        .count("DISTINCT (DATE(created_at), user_id)")
      (visitor_days.to_f / [days, 1].max).round(1)
    rescue => e
      Rails.logger.warn("avg_daily_visitors error: #{e.message}")
      0
    end

    def avg_visits_per_member_per_month(period_days = 30, range: nil)
      return 0 unless location
      member_count = active_member_count + active_lease_member_count
      return 0 if member_count == 0

      range, days = resolve_period(period_days, range)
      total_visit_days = DoorPunch.where(door: location.doors)
        .where(created_at: range)
        .count("DISTINCT (DATE(created_at), user_id)")

      months = [days / 30.0, 1].max
      ((total_visit_days.to_f / member_count) / months).round(1)
    rescue => e
      Rails.logger.warn("avg_visits_per_member_per_month error: #{e.message}")
      0
    end

    def new_members_count(period_days = 30, range: nil)
      range, _days = resolve_period(period_days, range)
      # Paid individual subscriptions only — the same population
      # churned_members_count draws from, so net_member_growth compares
      # like with like. (Previously this counted every plan including free
      # ones, so free signups inflated growth that no churn could offset.)
      Subscription.where(plan: plans.individual.nonzero, subscribable_type: "User")
        .where(created_at: range)
        .distinct.count(:subscribable_id)
    end

    def new_signups_count(period_days = 30)
      User.for_space(operator)
        .originally_at_location(location)
        .approved.visible
        .where("users.created_at > ?", period_days.days.ago)
        .count
    end

    def net_member_growth(period_days = 30, range: nil)
      new_members_count(period_days, range: range) - churned_members_count(period_days, range: range)
    end

    # Average monthly revenue per PAYING individual member. Membership
    # invoices only (revenue_by_product's exclusive "Memberships" bucket —
    # no leases, day passes, or rooms) over the last COMPLETE calendar
    # month, divided by the count of active paying individual subscribers.
    #
    # Numerator and denominator describe the same population: the people who
    # each pay an individual membership invoice. Comped/out-of-band members
    # and lease members are excluded from BOTH sides, so a sponsored member
    # never dilutes it. A complete month avoids the partial-month
    # understatement the old this_month_revenue-based tile suffered.
    def revenue_per_paying_member
      return 0 unless location
      members = paying_individual_member_count
      return 0 if members.zero?
      (last_complete_month_product_revenue.fetch("Memberships", 0.0) / members).round(2)
    end
    alias revenue_per_member revenue_per_paying_member

    # Average monthly revenue per active office lease — the "Office Leases"
    # bucket (invoiced + out-of-band check leases) over the last complete
    # month, divided by the number of active leases. Companion to
    # revenue_per_paying_member so a lease-heavy space (leases are ~76% of
    # revenue at CT) isn't summarized by membership ARPU alone.
    def revenue_per_lease
      return 0 unless location
      leases = active_lease_count
      return 0 if leases.zero?
      (last_complete_month_product_revenue.fetch("Office Leases", 0.0) / leases).round(2)
    end

    def paying_individual_member_count
      subscribed_members.visible.approved.count
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

    # Partition the window's paid invoices by what they actually paid for.
    # Hard linkage first (day-pass/bundle invoice ids, room-capture payment
    # intents), then billable type, remainder = memberships — every invoice
    # lands in exactly ONE bucket, so the rows sum to the same invoice
    # total the PERIOD REVENUE tile shows, plus the identical pro-rated
    # out-of-band lease supplement.
    #
    # The previous version summed ALL User-billed invoices as "Memberships"
    # while re-counting day passes at list price and rooms at rate×minutes
    # on top — double counting — and user-billed office-lease invoices
    # (how CT's leases are commonly billed) landed under Memberships.
    def revenue_by_product(period_days = 365, range: nil)
      return {} unless location
      range, _days = resolve_period(period_days, range)

      dp_invoice_ids = day_passes.where.not(invoice_id: nil).pluck(:invoice_id).to_set
      dp_invoice_ids |= DayPassBundle.where(location: location)
        .where.not(invoice_id: nil).pluck(:invoice_id)
      room_pi_ids = Reservation.joins(:room)
        .where(rooms: { location_id: location.id })
        .where.not(stripe_payment_intent_id: nil)
        .pluck(:stripe_payment_intent_id).to_set

      # User-billed lease invoices: the payer is the billing contact or
      # owner of an org holding a lease that overlaps the window. (An org
      # owner's own personal membership gets folded in here too — accepted
      # imprecision until invoices carry a product reference.)
      lease_org_ids = office_leases
        .where("start_date <= ? AND end_date >= ?", range.end.to_date, range.begin.to_date)
        .pluck(:organization_id).compact
      lease_contact_ids = Organization.where(id: lease_org_ids)
        .pluck(:billing_contact_id, :owner_id).flatten.compact.to_set

      result = Hash.new(0.0)
      paid_invoices_in(range)
        .pluck(:id, :amount_due, :billable_type, :billable_id, :stripe_payment_intent_id)
        .each do |id, amount, btype, bid, pi|
          bucket =
            if dp_invoice_ids.include?(id)
              "Day Passes"
            elsif pi.present? && room_pi_ids.include?(pi)
              "Meeting Rooms"
            elsif btype == "Organization"
              "Office Leases"
            elsif btype == "User" && lease_contact_ids.include?(bid)
              "Office Leases"
            else
              "Memberships"
            end
          result[bucket] += (amount || 0).to_f / 100.0
        end

      supplement = lease_supplement_for_window(range)
      result["Office Leases"] += supplement if supplement.positive?

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
      last_month_invoices = paid_invoices_in(1.month.ago.beginning_of_month..1.month.ago.end_of_month)
        .sum(:amount_due).to_f / 100.0
      return nil if last_month_invoices == 0
      ((current - last_month_invoices) / last_month_invoices * 100).round(1)
    end

    def inactive_member_ids
      return [] unless location
      cutoff = 30.days.ago

      active_ids = active_members.pluck(:id)
      return [] if active_ids.empty?

      # Drop out-of-band members whose only membership basis was a group office
      # lease that has since ended: they're former members, not lapsed ones, and
      # shouldn't surface on the re-engagement list. An out-of-band member counts
      # as inactive only if their org still holds an active lease, or they carry
      # their own active individual subscription.
      active_lease_org_ids = office_leases.active.pluck(:organization_id).compact
      stale_group_member_ids = User.where(id: active_ids)
        .where.not(organization_id: nil)
        .where.not(organization_id: active_lease_org_ids)
        .where.not(id: subscribed_members.select(:id))
        .pluck(:id)
      active_ids -= stale_group_member_ids
      return [] if active_ids.empty?

      door_active_ids = DoorPunch.where(user_id: active_ids)
        .where("created_at > ?", cutoff).distinct.pluck(:user_id)
      reservation_active_ids = Reservation.where(user_id: active_ids)
        .where("created_at > ?", cutoff).distinct.pluck(:user_id)

      visited_ids = (door_active_ids + reservation_active_ids).uniq
      active_ids - visited_ids
    end

    def inactive_members
      User.where(id: inactive_member_ids).order(:name)
    end

    def inactive_member_count
      inactive_member_ids.count
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

    # Period metrics historically took a trailing day count (`period_days`);
    # calendar periods like "last month" need an explicit window instead.
    # Returns [range, days-in-range]. With no range, preserves the trailing
    # behavior exactly.
    def resolve_period(period_days, range)
      if range
        days = (range.end.to_date - range.begin.to_date).to_i + 1
        # A Date..Date range compared against a timestamp column would cast
        # the end date to midnight and drop that whole day — expand to the
        # full days in Time.zone.
        if range.begin.is_a?(Date) && range.end.is_a?(Date)
          range = range.begin.beginning_of_day..range.end.end_of_day
        end
        [range, [days, 1].max]
      else
        [period_days.days.ago..Time.current, period_days]
      end
    end

    # Out-of-band lease checks aren't invoiced; add each overlapped month's
    # supplement pro-rated by the fraction of the month inside the window,
    # so a 30-day window spanning two months doesn't count two full months
    # of check revenue. Iteration starts at the earliest lease — "All Time"
    # windows would otherwise walk hundreds of empty months.
    def lease_supplement_for_window(range)
      period_start = range.begin.to_date
      period_end = range.end.to_date
      earliest_lease = office_leases.minimum(:start_date)
      return 0.0 unless earliest_lease

      lease_rev = 0.0
      month = [period_start, earliest_lease.beginning_of_month].max.beginning_of_month
      last_month = period_end.beginning_of_month
      while month <= last_month
        overlap_start = [month, period_start].max
        overlap_end = [month.end_of_month, period_end].min
        if overlap_end >= overlap_start
          overlap_days = (overlap_end - overlap_start).to_i + 1
          fraction = overlap_days / month.end_of_month.day.to_f
          lease_rev += lease_supplement_for_month(month) * fraction
        end
        month = month.next_month
      end
      lease_rev
    end

    # revenue_by_product for the last COMPLETE calendar month, memoized so
    # revenue_per_paying_member and revenue_per_lease share one query pass.
    def last_complete_month_product_revenue
      @last_complete_month_product_revenue ||= begin
        last_month = Date.current.prev_month
        revenue_by_product(range: last_month.beginning_of_month..last_month.end_of_month)
      end
    end

    def purchased_day_pass_revenue(range)
      day_passes.purchased.joins(:day_pass_type)
        .where(day: range)
        .sum("day_pass_types.amount_in_cents").to_f / 100.0
    end

    # How many past years to sample when measuring a month's historical
    # index, how strongly to shrink the index toward "no seasonal effect",
    # and how many months of surrounding history a sample year needs before
    # it counts (a location's nascent first months produce junk ratios).
    FORECAST_LOOKBACK_YEARS = 3
    FORECAST_INDEX_PRIOR_WEIGHT = 1.0
    FORECAST_MIN_SAMPLE_MONTHS = 6

    # Generic month forecaster: recent baseline × historical index for the
    # target calendar month.
    #
    # Baseline: mean of the last up-to-12 COMPLETE months, clipped to the
    # series' first month so pre-opening zeros don't drag it down. It spans
    # a full seasonal cycle for mature locations, so it's naturally
    # season-free, and growth/decline shows up in it automatically.
    #
    # Index: for each of the last few years, the target month's revenue
    # divided by the mean of the 12 months ending then — "how did this
    # month compare to its own year?" — averaged, then shrunk toward 1.0
    # by sample count and clamped. With no usable samples (young location)
    # the index is 1.0 and the forecast is just the recent average.
    def forecast_from_history(target_month, revenue_for_month:, first_month:)
      return 0 unless first_month
      target = target_month.to_date.beginning_of_month
      first = first_month.to_date.beginning_of_month
      last_complete = Date.current.beginning_of_month.prev_month
      return 0 if last_complete < first

      history = []
      m = last_complete
      while m >= first && history.size < 12
        history << revenue_for_month.call(m)
        m = m.prev_month
      end
      baseline = history.sum / history.size
      return 0 if baseline.zero?

      ratios = []
      (1..FORECAST_LOOKBACK_YEARS).each do |k|
        sample = target << (12 * k)
        next if sample < first || sample > last_complete

        window = []
        m = sample
        12.times do
          window << revenue_for_month.call(m) if m >= first
          m = m.prev_month
        end
        next if window.size < FORECAST_MIN_SAMPLE_MONTHS

        year_avg = window.sum / window.size
        ratios << revenue_for_month.call(sample) / year_avg if year_avg.positive?
      end

      index = if ratios.any?
        raw = ratios.sum / ratios.size
        shrunk = (raw * ratios.size + FORECAST_INDEX_PRIOR_WEIGHT) /
          (ratios.size + FORECAST_INDEX_PRIOR_WEIGHT)
        shrunk.clamp(0.25, 4.0)
      else
        1.0
      end

      (baseline * index).round
    end

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

      # Find org IDs that already have invoices this month. Must use the
      # same effective-date key as the revenue sums: a lease org that paid
      # by card gets an invoice with NULL due_date, and keying this check
      # on due_date alone made those invisible — so the org's lease was
      # ALSO added as a "check payment" and double-counted.
      month_invoices = paid_invoices_in(month_start.beginning_of_day..month_end.end_of_day)
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
        # Orphaned rows (nil organization) exist in prod — no org means no
        # payer to attribute, so they don't belong in revenue.
        next if lease.organization_id.nil?
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