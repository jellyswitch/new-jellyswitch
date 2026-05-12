
class Operator::SearchResultsController < Operator::BaseController
  before_action :require_authentication
  before_action :background_image

  def new

  end

  def create
    @query = params[:query]
    turbo_redirect(query_search_results_path(query: @query), action: "advance")
  end

  def query
    @query = params[:query]
    results = Searchkick.search(
      @query,
      fields: [
        :name,
        :text,
        :comments,
        :user_name,
        :type,
        :amount,
        :stripe_customer_id,
        :email,
        :organization,
        :owner,
        :announcement],
      models: [FeedItem, User, Organization, Room, Door, Location, Announcement],
      where: { operator_id: current_tenant.id },
      operator: "or"
    )

    # Operator-level search returns results from all sibling locations under
    # the same operator (e.g. Untethered Zephyr Cove + Untethered Fulton).
    # Scope to the current location. Searchkick docs don't have location_id
    # indexed yet (TODO: add to search_data + reindex for index-level
    # filtering), so we filter in Ruby after the search.
    loc_id = current_location&.id
    @results = results.select do |r|
      case r
      when Location
        r.id == loc_id
      when User
        # Users belong to an operator, not strictly a location, but they
        # have a home location — match on that.
        r.original_location_id == loc_id
      else
        # FeedItem, Organization, Room, Door, Announcement all have
        # location_id and are strictly per-location.
        r.respond_to?(:location_id) ? r.location_id == loc_id : true
      end
    end.sort_by { |r| r.created_at || Time.at(0) }.reverse
    render :create, status: 200
  end
end