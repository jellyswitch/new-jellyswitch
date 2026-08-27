module Embed
  # Public Concierge capture endpoint. The widget is a JS app, so this returns
  # JSON. Mirrors the tour-request widget's perimeter (no auth, CSRF-skipped,
  # honeypot, Turnstile, framing) and CRM capture (find/create User + Activity).
  class ConciergeController < ActionController::Base
    # Self-serve intents go to checkout. Everything else (questions, room/office
    # requests, "message the team") becomes a MemberFeedback so it lands in the
    # operator's existing Feedback/Messages channel + alerts staff there.
    SELF_SERVE_INTENTS = %w[day_pass day_pass_bundle membership].freeze

    layout "embed"

    skip_before_action :verify_authenticity_token, raise: false

    before_action :load_operator
    before_action :require_concierge_active_or_preview, only: [:show]
    before_action :require_concierge_active, only: [:create, :checkout, :purchase]
    after_action  :allow_framing

    helper_method :admin_previewing?

    # Short-lived signed token so the settings-page preview iframe can render the
    # widget without depending on session cookies crossing the embed boundary.
    def self.verifier
      Rails.application.message_verifier(:concierge_preview)
    end

    def show
      @theme = {
        primary: @operator.embed_primary_color,
        accent: @operator.embed_accent_color,
        font: @operator.embed_font_family,
      }
      visible = @operator.locations.where(visible: true).order(:name)
      @location = @operator.locations.find_by(id: params[:location_id])
      # A global (unpinned) embed at a multi-location operator must not guess a
      # location: catalog, prices, the offer, and lead/question routing are all
      # location-scoped, so ask the visitor first. Picking navigates to the
      # location-pinned URL and everything downstream stays server-resolved.
      if @location.nil? && visible.count > 1
        @locations = visible
        return render :choose_location
      end
      @location ||= visible.first
      @options = Concierge::Recommender.new(operator: @operator, location: @location).options
      render :show
    end

    # One-line embed for operator marketing sites: a <script> tag that injects a
    # floating chat bubble which opens the widget in a panel. Served as JS (not
    # an iframe snippet) so site owners paste a single line and every page gets
    # the launcher. When the Concierge is off this renders a no-op instead of a
    # 404 so embedded sites never log script errors.
    def launcher
      expires_in 10.minutes, public: true
      unless @operator.concierge_active?
        return render(js: "/* Concierge is not enabled for #{@operator.subdomain} */")
      end

      # Resolve the location so the teaser can carry a per-location offer.
      @location = @operator.locations.find_by(id: params[:location_id])
      @widget_url = embed_concierge_url(
        operator_subdomain: @operator.subdomain,
        host: request.host_with_port,
        location_id: params[:location_id].presence,
      )
      render :launcher, formats: [:js], layout: false
    end

    # Public checkout page (Stripe Elements). Product = day pass, bundle, or
    # membership (plan), pre-selected via day_pass_type_id or plan_id.
    def checkout
      @location = checkout_location
      @product = checkout_product
      return head(:not_found) unless @product && @location&.stripe_setup?
      render :checkout
    end

    # Create account + charge, reusing the existing billing chains.
    def purchase
      return head(:ok) if params[:_hp].present? # honeypot
      location = checkout_location
      product = checkout_product
      unless location && product
        return render(json: { ok: false, error: "invalid" }, status: :unprocessable_entity)
      end

      args = { operator: @operator, location: location, email: params[:email],
               name: params[:name], password: params[:password], phone: params[:phone],
               terms_accepted: params[:terms_accepted], token: params[:stripe_token] }
      args[product.is_a?(Plan) ? :plan : :day_pass_type] = product
      args[:day] = checkout_day if checkout_day
      result = Concierge::PublicCheckout.call(args)

      if result.success?
        log_purchase_chat(result.user, product, location)
        render json: { ok: true, app: { ios: @operator.ios_url, android: @operator.android_url } }
      else
        render json: { ok: false, error: result.error, message: result.message }, status: :unprocessable_entity
      end
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
                                :message, :location_id, :marketing_opt_in, transcript: [])

      if permitted[:email].blank?
        return render(json: { ok: false, error: "email_required" }, status: :unprocessable_entity)
      end

      location = @operator.locations.find_by(id: permitted[:location_id])
      user = upsert_person(permitted, location)
      log_chat(user, permitted, location) # keeps the conversion-lift metric working
      # Seed the Person's Interest from what they asked about (office /
      # conference room / day pass / membership) so they land on the right list.
      InterestTag.record_from_concierge_intent(user, permitted[:intent])

      self_serve = SELF_SERVE_INTENTS.include?(permitted[:intent].to_s)
      route_to_feedback(user, permitted, location) unless self_serve

      render json: {
        ok: true,
        intent: permitted[:intent],
        self_serve: self_serve,
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

    # A question / room request / "message the team" becomes a MemberFeedback so
    # it shows up in the operator's existing Feedback/Messages inbox and pings
    # staff there (CreateNotificationsAsync), instead of a separate channel.
    def route_to_feedback(user, permitted, location)
      feedback = MemberFeedback.new(
        comment: feedback_comment(permitted[:intent].to_s, permitted[:message]),
        user: user, operator: @operator, location: location,
      )
      CreateNotificationsAsync.call(notifiable: feedback) if feedback.save
    end

    def feedback_comment(intent, message)
      label = {
        "day_office" => "Day office request",
        "conference_room" => "Conference room request",
        "office" => "Office / long-term request",
      }[intent]
      parts = [label, message.to_s.strip.presence].compact
      parts.empty? ? "Question from the website Concierge" : parts.join(": ")
    end

    def checkout_location
      @operator.locations.find_by(id: params[:location_id]) ||
        @operator.locations.where(visible: true).order(:name).first
    end

    # The buyer's chosen day for a single day pass. Clamped to today..+60d;
    # anything unparseable or out of range falls back to the interactor's
    # Date.current default rather than failing the purchase.
    def checkout_day
      return @checkout_day if defined?(@checkout_day)
      @checkout_day = begin
        day = Date.iso8601(params[:day].to_s)
        day if day >= Date.current && day <= Date.current + 60
      rescue ArgumentError, TypeError
        nil
      end
    end

    # The conversion-lift metric cohorts on "has a chat Activity". Buyers who
    # came straight through checkout (or whose pre-checkout capture failed)
    # would otherwise count as non-chatters and deflate the Concierge's own
    # lift number — log their first chat here. No-op if they already have one.
    def log_purchase_chat(user, product, location)
      return unless user
      return if Activity.where(user: user, kind: :chat).exists?

      intent = if product.is_a?(Plan) then "membership"
               elsif product.bundle? then "day_pass_bundle"
               else "day_pass"
               end
      Activity.log(
        user: user, operator: @operator, kind: :chat, occurred_at: Time.current,
        subject: location,
        payload: { "intent" => intent, "recommended_product" => product.name,
                   "source" => "concierge_checkout", "referrer" => request.referer },
      )
    end

    # The selected product: a Plan (membership) when plan_id is given, otherwise
    # a DayPassType (single pass or bundle). Both respond to name + amount_in_cents.
    def checkout_product
      if params[:plan_id].present?
        @operator.plans.for_individuals.find_by(id: params[:plan_id])
      else
        @operator.day_pass_types.available.visible
                 .where(location_id: checkout_location&.id).find_by(id: params[:day_pass_type_id])
      end
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
