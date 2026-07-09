# Mobile parity for the web "Office queue" (People > Office queue). The office
# waitlist is just InterestTag.for_product("office"), presented as a fairness
# queue worked one person at a time. Admin-gated by the inherited BaseController
# (require_admin!). See OfficeWaitlist (app/queries) + OfficeOutreach (app/services).
class Api::V1::Admin::OfficeWaitlistController < Api::V1::Admin::BaseController
  def index
    waitlist = OfficeWaitlist.for(current_tenant)
    render json: {
      entries: waitlist.entries.map { |entry| entry_json(entry) },
      demand: waitlist.demand,
      available_offices: Office.available_for_lease.map { |office| { id: office.id, name: office.name } },
    }
  end

  # Offer the freed office to a waiting person (records office_offered).
  def offer
    person = current_tenant.users.find(params[:user_id])
    office = current_tenant.offices.find_by(id: params[:office_id])
    OfficeOutreach.offer!(user: person, office: office, added_by: current_api_user)
    render json: { success: true, status: OfficeOutreach.status_for(person) }
  end

  # Record that a person declined an office offer (records office_declined).
  def decline
    person = current_tenant.users.find(params[:user_id])
    OfficeOutreach.decline!(user: person, added_by: current_api_user)
    render json: { success: true, status: OfficeOutreach.status_for(person) }
  end

  private

  def entry_json(entry)
    user = entry.user
    {
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        member_since: user.created_at&.iso8601,
        has_profile_photo: user.has_profile_photo?,
      },
      status: entry.status,
      source: entry.source,
      waiting_days: entry.waiting_days,
      waiting_since: entry.waiting_since&.iso8601,
      customer: entry.customer?,
    }
  end
end
