module Embed
  # Office Inventory: serves JS that renders the location's available offices
  # inline into the host page (ADR 0027), and takes inquiries as a plain
  # top-level form POST (tour-widget perimeter: no auth, CSRF-skipped,
  # honeypot; Rack::Attack's /embed/* throttle covers it).
  class OfficeInventoryController < ActionController::Base
    layout false

    skip_forgery_protection

    before_action :load_operator

    def widget
      expires_in 5.minutes, public: true
      return render_noop("Office Inventory is not enabled for #{@operator.subdomain}") unless @operator.office_inventory_enabled?

      visible = @operator.locations.where(visible: true).order(:name)
      @location = @operator.locations.find_by(id: params[:location_id])
      if @location.nil? && visible.count > 1
        @nudge_locations = visible
        return render :nudge
      end
      @location ||= visible.first
      return render_noop("No visible location for #{@operator.subdomain}") unless @location

      @offices = listed_offices
      render :widget
    end

    def inquire
      return head(:ok) if params[:_hp].present? # honeypot

      office = @operator.offices.where(location_id: params[:location_id]).find_by(id: params[:office_id])
      email = params[:email].to_s.downcase.strip
      if office.nil? || email.blank? || params[:name].blank?
        return redirect_to embed_office_inventory_thank_you_path(operator_subdomain: @operator.subdomain, ok: 0)
      end

      user = User.find_or_initialize_by(email: email, operator: @operator)
      if user.new_record?
        user.name = params[:name]
        user.original_location_id = office.location_id
        user.admin_created = true
        user.password = SecureRandom.hex(16)
        user.phone = params[:phone] if params[:phone].present?
      end
      user.save!

      # The inquiry lands in the operator's existing Feedback/Messages inbox
      # and pings the location's team (relevant_admins_of_location); the
      # interest tag feeds the office waitlist (the People list filtered to
      # the office tag).
      feedback = MemberFeedback.new(
        user: user, operator: @operator, location: office.location,
        comment: inquiry_comment(office),
      )
      CreateNotificationsAsync.call(notifiable: feedback) if feedback.save
      InterestTag.record(user: user, product: "office", source: "looked_at")

      redirect_to embed_office_inventory_thank_you_path(operator_subdomain: @operator.subdomain)
    end

    def thank_you
      render :thank_you, layout: "embed", formats: [:html]
    end

    private

    def load_operator
      @operator = Operator.find_by!(subdomain: params[:operator_subdomain])
    end

    def render_noop(message)
      render js: "/* #{message} */"
    end

    def listed_offices
      @operator.offices.where(location: @location).where(visible: true)
               .includes(:office_leases).with_attached_photo
               .filter_map do |office|
        availability = office.listed_availability
        next unless availability

        {
          id: office.id,
          name: office.name,
          capacity: office.capacity,
          square_footage: office.square_footage,
          description: office.description,
          rate_label: office.asking_rate_in_cents ? "$#{office.asking_rate_in_cents / 100}/mo" : "Contact for pricing",
          availability_label: availability == :now ? "Available now" : "Available from #{availability.strftime('%b %-d, %Y')}",
          photo_url: office.photo.attached? ? rails_blob_url(office.photo, host: request.host_with_port) : nil,
        }
      end
    end

    def inquiry_comment(office)
      details = ["Office inquiry — #{office.name}"]
      details << "#{office.capacity} people" if office.capacity.to_i.positive?
      details << "#{office.square_footage} sqft" if office.square_footage.to_i.positive?
      details << (office.asking_rate_in_cents ? "asking $#{office.asking_rate_in_cents / 100}/mo" : "no listed rate")
      line = details.join(", ")
      message = params[:message].to_s.strip
      message.present? ? "#{line}: #{message}" : line
    end
  end
end
