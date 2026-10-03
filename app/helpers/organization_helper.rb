
module OrganizationHelper
  def add_member_options(organization)
    # Only members of the group's own space (Untethered runs Lake Tahoe and
    # Fulton under one operator) — same scoping as the lease member picker.
    location = organization.location || current_location
    current_tenant.users.visible.originally_at_location(location).not_in_organization(organization).order(name: :asc).map do |user|
      ["#{user.name} (#{user.email})", user.id]
    end
  end
end
