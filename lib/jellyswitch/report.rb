module Jellyswitch
  class Report
    attr_accessor :operator

    delegate :plans, :office_leases, :day_passes, :users, :square_footage, :name, to: :operator

    def initialize(operator)
      @operator = operator
    end

    def active_members
      plans.individual.map do |plan|
        plan.subscriptions.active.map(&:subscribable)
      end.flatten.uniq
    end

    def active_member_count
      active_members.count
    end

    def active_leases
      office_leases.active
    end

    def active_lease_count
      active_leases.count
    end

    def active_lease_members
      office_leases.active.map do |lease|
        lease.organization.users
      end.flatten.uniq
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

    def all_members
      users.members.non_superadmins
    end

    def all_member_count
      all_members.count
    end

    def staff
      users.admins.non_superadmins
    end
    
    def staff_count
      staff.count
    end
  end
end