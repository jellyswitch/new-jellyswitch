module Embed
  # Public Concierge capture endpoint. The widget is a JS app, so this returns
  # JSON. Mirrors the tour-request widget's perimeter (no auth, CSRF-skipped,
  # honeypot, Turnstile, framing) and CRM capture (find/create User + Activity).
  class ConciergeController < ActionController::Base
    # Intents the operator handles by hand (rooms aren't automated, office needs
    # a tour) — these ping staff. Self-serve intents capture silently.
    ADMIN_HANDLED_INTENTS = %w[day_office conference_room office].freeze

    skip_before_action :verify_authenticity_token, raise: false

    before_action :load_operator
    before_action :require_concierge_active
    after_action  :allow_framing

    def create
      return head(:ok) if params[:_hp].present? # honeypot

      turnstile = Turnstile::Verifier.call(
        token: params["cf-turnstile-response"],
        remote_ip: request.remote_ip,
        context: "concierge",
      )
      return render(json: { ok: false, error: "captcha" }, status: :unprocessable_entity) unless turnstile.success?

      permitted = params.permit(:name, :email, :phone, :intent, :recommended_product,
                                :location_id, :marketing_opt_in, transcript: [])

      if permitted[:email].blank?
        return render(json: { ok: false, error: "email_required" }, status: :unprocessable_entity)
      end

      location = @operator.locations.find_by(id: permitted[:location_id])
      user = upsert_person(permitted, location)
      activity = log_chat(user, permitted, location)

      if ADMIN_HANDLED_INTENTS.include?(permitted[:intent].to_s)
        SendNotificationsJob.perform_later(activity, "ConciergeAlert")
      end

      render json: {
        ok: true,
        intent: permitted[:intent],
        self_serve: !ADMIN_HANDLED_INTENTS.include?(permitted[:intent].to_s),
        # Interim CTA until the public web checkout (Phase 3) exists.
        app: { ios: @operator.ios_url, android: @operator.android_url },
      }
    end

    private

    def upsert_person(permitted, location)
      user = User.find_or_initialize_by(email: permitted[:email].downcase.strip, operator: @operator)
      if user.new_record?
        user.name = permitted[:name].presence || permitted[:email]
        user.original_location_id = location&.id
        user.admin_created = true
        user.password = SecureRandom.hex(16)
        user.phone = permitted[:phone] if permitted[:phone].present?
        # Default opted-in (matches signup); honor an explicit opt-out only.
        if permitted[:marketing_opt_in].present? && !ActiveModel::Type::Boolean.new.cast(permitted[:marketing_opt_in])
          user.email_opted_out = true
        end
      end
      user.save!
      user
    end

    def log_chat(user, permitted, location)
      Activity.log(
        user: user,
        operator: @operator,
        kind: :chat,
        occurred_at: Time.current,
        subject: location,
        payload: {
          "intent" => permitted[:intent],
          "recommended_product" => permitted[:recommended_product],
          "transcript" => Array(permitted[:transcript]),
          "source" => "concierge",
          "referrer" => request.referer,
        },
      )
    end

    def load_operator
      @operator = Operator.find_by(subdomain: params[:operator_subdomain])
      head :not_found and return unless @operator
      ActsAsTenant.current_tenant = @operator
    end

    def require_concierge_active
      head :not_found unless @operator.concierge_active?
    end

    def allow_framing
      response.headers["X-Frame-Options"] = "ALLOWALL"
      response.headers.delete("Content-Security-Policy")
    end
  end
end
