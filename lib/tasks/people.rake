namespace :people do
  desc "Assign default point-of-contact to all existing Users who have none. Idempotent."
  task assign_default_points_of_contact: :environment do
    scope = User.where(point_of_contact_id: nil)
                .where.not(role: User::STAFF_ROLES)
    total = scope.count
    puts "Assigning default points-of-contact for #{total} Person(s)..."

    assigned = 0
    skipped = 0
    scope.find_each do |user|
      ActsAsTenant.with_tenant(user.operator) do
        before = user.point_of_contact_id
        user.assign_default_point_of_contact!
        if user.reload.point_of_contact_id != before
          assigned += 1
          puts "  - assigned ##{user.id} #{user.email} → ##{user.point_of_contact_id}"
        else
          skipped += 1
        end
      end
    end

    puts "Done. assigned=#{assigned} skipped=#{skipped} (no GM or admin candidate found)"
  end
end
