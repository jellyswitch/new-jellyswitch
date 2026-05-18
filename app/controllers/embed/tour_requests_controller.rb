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

    def create
      # Honeypot: silent drop if filled.
      return head(:ok) if params[:_hp].present?

      # Turnstile verification (short-circuits when secret unset, e.g. test/dev).
      turnstile = Turnstile::Verifier.call(
        token: params["cf-turnstile-response"],
        remote_ip: request.remote_ip,
      )
      unless turnstile.success?
        flash.now[:error] = "Please retry the captcha."
        @pinned_location = @operator.locations.find_by(id: params[:location_id])
        return render(:show, status: :unprocessable_entity)
      end

      permitted = params.permit(:name, :email, :phone, :message, :location_id)
      location = @operator.locations.find_by(id: permitted[:location_id])

      if permitted[:email].blank? || permitted[:name].blank?
        flash.now[:error] = "Name and email are required."
        @pinned_location = location
        return render(:show, status: :unprocessable_entity)
      end

      user = User.find_or_initialize_by(email: permitted[:email].downcase.strip, operator: @operator)
      if user.new_record?
        user.name = permitted[:name]
        user.original_location_id = location&.id
        user.admin_created = true
        user.password = SecureRandom.hex(16)
        user.phone = permitted[:phone] if permitted[:phone].present?
      end
      user.save!

      activity = Activity.log(
        user: user,
        operator: @operator,
        kind: :tour_request,
        occurred_at: Time.current,
        subject: location,
        payload: {
          "message"  => permitted[:message],
          "source"   => "widget",
          "referrer" => request.referer,
        },
      )

      SendNotificationsJob.perform_later(activity, "TourRequestAlert")

      if @operator.tour_widget_thank_you_url.present?
        redirect_to @operator.tour_widget_thank_you_url, allow_other_host: true, status: :see_other
      else
        redirect_to embed_tour_request_thank_you_path(operator_subdomain: @operator.subdomain), status: :see_other
      end
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
