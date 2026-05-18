module Embed
  class TourRequestsController < ActionController::Base
    # Public endpoint — no app layout, no auth.
    layout "embed"

    skip_before_action :verify_authenticity_token, raise: false

    before_action :load_operator
    before_action :require_widget_active
    before_action :load_locations
    after_action  :allow_framing

    def show
      @pinned_location = @operator.locations.find_by(id: params[:location_id]) if params[:location_id]
      render :show
    end

    def thank_you
      render :thank_you
    end

    private

    def load_operator
      @operator = Operator.find_by(subdomain: params[:operator_subdomain])
      head :not_found and return unless @operator
      ActsAsTenant.current_tenant = @operator
    end

    def require_widget_active
      head :not_found and return unless @operator.tour_widget_active?
    end

    def load_locations
      @locations = @operator.locations.where(visible: true).order(:name)
    end

    def allow_framing
      response.headers["X-Frame-Options"] = "ALLOWALL"
      response.headers.delete("Content-Security-Policy")
    end
  end
end
