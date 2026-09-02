module Embed
  class TourRequestsController < ActionController::Base
    # Public endpoint — no app layout, no auth.
    layout "embed"

    skip_before_action :verify_authenticity_token, raise: false

    before_action :load_operator
    before_action :require_widget_active_or_admin_preview
    before_action :load_locations
    after_action  :allow_framing

    helper_method :admin_previewing?

    # Used by the settings view to build the iframe URL.
    def self.verifier
      Rails.application.message_verifier(:tour_widget_preview)
    end

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
        context: "tour_request",
      )
      unless turnstile.success?
        flash.now[:error] = "Please retry the captcha."
        @pinned_location = @operator.locations.find_by(id: params[:location_id])
        return render(:show, status: :unprocessable_entity)
      end

      permitted = params.permit(:name, :email, :phone, :message, :preferred_time, :location_id)
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
          "message"        => permitted[:message],
          "preferred_time" => permitted[:preferred_time].presence,
          "source"         => "widget",
          "referrer"       => request.referer,
        },
      )

      # Untethered-only: Zephyr Cove requests are also logged at Cowork Tahoe
      # (ADR 0030). Runs before the alert so the staff email can link to it.
      TourRequests::SisterSpaceMirror.call(activity)

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

    # Public traffic gets a 404 when the widget is disabled, but an operator
    # admin viewing the settings page's live preview iframe needs to see the
    # widget regardless — otherwise the preview is blank until they enable
    # it, which is exactly the moment they want to look at it.
    def require_widget_active_or_admin_preview
      return if @operator.tour_widget_active?
      return if admin_previewing?
      head :not_found
    end

    # Settings page generates a short-lived signed token for the iframe URL
    # so we don't depend on session cookies traversing the embed boundary
    # (the cookie's domain scope and the embed's frame context don't always
    # play nicely). The token is operator-scoped so it can't preview another
    # operator's widget.
    def admin_previewing?
      token = params[:preview_token]
      return false if token.blank?

      payload = Embed::TourRequestsController.verifier.verify(token).with_indifferent_access
      payload[:operator_id] == @operator.id && payload[:exp].to_i > Time.current.to_i
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
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
