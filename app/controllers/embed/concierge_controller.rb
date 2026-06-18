module Embed
  # Public Concierge capture endpoint. The widget is a JS app, so this returns
  # JSON. Mirrors the tour-request widget's perimeter (no auth, CSRF-skipped,
  # honeypot, Turnstile, framing) and CRM capture (find/create User + Activity).
  class ConciergeController < ActionController::Base
    # Intents the operator handles by hand (rooms aren't automated, office needs
    # a tour) — these ping staff. Self-serve intents capture silently.
    ADMIN_HANDLED_INTENTS = %w[day_office conference_room office].freeze

    layout "embed"

    skip_before_action :verify_authenticity_token, raise: false

    before_action :load_operator
    before_action :require_concierge_active_or_preview, only: [:show]
    before_action :require_concierge_active, only: [:create, :start_conversation, :post_message, :poll_messages, :checkout, :purchase]
    after_action  :allow_framing

    helper_method :admin_previewing?

    # Short-lived signed token so the settings-page preview iframe can render the
    # widget without depending on session cookies crossing the embed boundary.
    def self.verifier
      Rails.application.message_verifier(:concierge_preview)
    end

    def show
      @location = @operator.locations.find_by(id: params[:location_id]) ||
                  @operator.locations.where(visible: true).order(:name).first
      @options = Concierge::Recommender.new(operator: @operator, location: @location).options
      @theme = {
        primary: @operator.embed_primary_color,
        accent: @operator.embed_accent_color,
        font: @operator.embed_font_family,
      }
      render :show
    end

    # Public day-pass checkout page (Stripe Elements). Pre-selected product.
    def checkout
      @location = checkout_location
      @day_pass_type = @operator.day_pass_types.available.visible
                                .where(location_id: @location&.id).find_by(id: params[:day_pass_type_id])
      return head(:not_found) unless @day_pass_type && @location&.stripe_publishable_key.present?
      render :checkout
    end

    # Create account + charge, reusing the existing billing chain.
    def purchase
      return head(:ok) if params[:_hp].present? # honeypot
      location = checkout_location
      day_pass_type = @operator.day_pass_types.find_by(id: params[:day_pass_type_id])
      unless location && day_pass_type
        return render(json: { ok: false, error: "invalid" }, status: :unprocessable_entity)
      end

      result = Concierge::PublicDayPassCheckout.call(
        operator: @operator, location: location, day_pass_type: day_pass_type,
        email: params[:email], name: params[:name], password: params[:password],
        token: params[:stripe_token],
      )

      if result.success?
        render json: { ok: true, app: { ios: @operator.ios_url, android: @operator.android_url } }
      else
        render json: { ok: false, error: result.error, message: result.message }, status: :unprocessable_entity
      end
    end

    # Live chat: start a conversation. During open hours we greet + alert staff;
    # off-hours the widget shows the capture fallback (open_now: false).
    def start_conversation
      location = @operator.locations.find_by(id: params[:location_id]) ||
                 @operator.locations.where(visible: true).order(:name).first
      convo = ConciergeConversation.create!(operator: @operator, location: location)
      open_now = location&.open_now? || false

      if open_now
        convo.messages.create!(operator: @operator, role: "bot",
                               body: "You're chatting with the #{@operator.concierge_display_name} team 👋 — usually just a few minutes.")
        alert_staff(convo)
      end

      render json: { token: convo.session_token, open_now: open_now, status: convo.status,
                     messages: serialize(convo.messages) }
    end

    def post_message
      convo = find_conversation
      return head(:not_found) unless convo

      msg = convo.messages.create!(operator: @operator, role: "visitor", body: params[:body].to_s)
      convo.update!(last_visitor_message_at: Time.current)
      alert_staff(convo) if convo.location&.open_now? && !convo.staff_alerted?

      render json: { ok: true, message: serialize_message(msg),
                     awaiting_staff_timeout: convo.awaiting_staff_timeout? }
    end

    def poll_messages
      convo = find_conversation
      return head(:not_found) unless convo

      after = params[:after].to_i
      msgs = convo.messages.where("id > ?", after)
      render json: { messages: serialize(msgs), status: convo.status,
                     awaiting_staff_timeout: convo.awaiting_staff_timeout? }
    end

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

    def find_conversation
      ConciergeConversation.where(operator: @operator).find_by(session_token: params[:token])
    end

    def checkout_location
      @operator.locations.find_by(id: params[:location_id]) ||
        @operator.locations.where(visible: true).order(:name).first
    end

    def alert_staff(convo)
      SendNotificationsJob.perform_later(convo, "ConciergeChatAlert")
      convo.update!(staff_alerted: true)
    end

    def serialize(messages)
      messages.map { |m| serialize_message(m) }
    end

    def serialize_message(message)
      {
        id: message.id, role: message.role, body: message.body,
        author: message.author&.name, at: message.created_at.iso8601,
      }
    end

    def load_operator
      @operator = Operator.find_by(subdomain: params[:operator_subdomain])
      head :not_found and return unless @operator
      ActsAsTenant.current_tenant = @operator
    end

    def require_concierge_active
      head :not_found unless @operator.concierge_active?
    end

    def require_concierge_active_or_preview
      return if @operator.concierge_active?
      return if admin_previewing?
      head :not_found
    end

    # Operator-scoped signed token (1h) lets the settings preview show the
    # widget even while it's disabled — the moment they most want to look.
    def admin_previewing?
      token = params[:preview_token]
      return false if token.blank?

      payload = self.class.verifier.verify(token).with_indifferent_access
      payload[:operator_id] == @operator.id && payload[:exp].to_i > Time.current.to_i
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end

    def allow_framing
      response.headers["X-Frame-Options"] = "ALLOWALL"
      response.headers.delete("Content-Security-Policy")
    end
  end
end
