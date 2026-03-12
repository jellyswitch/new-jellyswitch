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
      location_invoices.paid.where(due_date: Time.current.beginning_of_month..Time.current.end_of_month).sum(:amount_due).to_f / 100.0
    end

    def revenue_by_month
      location_invoices.paid.where(due_date: 12.months.ago..).group_by_month(:due_date).sum(:amount_due).transform_values do |amt|
        amt.to_f / 100.0
      end
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
  end
end