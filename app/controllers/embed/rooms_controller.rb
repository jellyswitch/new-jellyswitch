module Embed
  # Conference Rooms: serves JS that renders the location's rentable meeting
  # rooms inline into the host page (ADR 0027 — on-page content, no iframe):
  # photo, capacity, hourly rate, description, feature list, and a Book now
  # link into the brand's own booking wizard. Read-only: the booking itself
  # happens on the brand site behind its login, which stores the return path
  # so a new visitor lands back in the wizard for that room after signing up.
  class RoomsController < ActionController::Base
    layout false

    # Cross-origin <script> embedding is this endpoint's entire purpose —
    # Rails' same-origin JS guard must not block it. No state changes here.
    skip_forgery_protection

    include Embed::AdminPreview

    before_action :load_operator

    def widget
      # Settings-page preview: signed token, never cached, shows the widget
      # even while it's disabled. Public traffic keeps a 1-minute cache so
      # room edits show up fast.
      if admin_previewing?
        expires_now
      else
        expires_in 1.minute, public: true
        return render_noop("Conference Rooms is not enabled for #{@operator.subdomain}") unless @operator.conference_rooms_enabled?
      end

      visible = @operator.locations.where(visible: true).order(:name)
      @location = @operator.locations.find_by(id: params[:location_id])
      if @location.nil? && visible.count > 1
        @nudge_locations = visible
        return render :nudge
      end
      @location ||= visible.first
      return render_noop("No visible location for #{@operator.subdomain}") unless @location

      @rooms = listed_rooms
      render :widget
    end

    private

    def load_operator
      @operator = Operator.find_by!(subdomain: params[:operator_subdomain])
    end

    def render_noop(message)
      render js: "/* #{message} */"
    end

    # Rentable = the room form's "available to rent for non-members" box, the
    # rooms a website visitor can actually book and pay for. Members-only
    # rooms stay in the app.
    def listed_rooms
      @operator.rooms.where(location: @location).visible.rentable
               .includes(:amenities).with_attached_photo
               .order(:capacity, :name)
               .map do |room|
        {
          id: room.id,
          name: room.name,
          capacity: room.capacity,
          square_footage: room.square_footage,
          description: room.description,
          rate_label: rate_label(room),
          bullets: room.website_bullets,
          photo_url: room.photo.attached? ? rails_blob_url(room.photo, host: request.host_with_port) : nil,
          book_url: booking_url(room),
        }
      end
    end

    def rate_label(room)
      cents = room.hourly_rate_in_cents.to_i
      return "Included with a day pass" if cents.zero? && room.include_with_day_pass?
      return "Included with membership" if cents.zero?

      dollars = cents % 100 == 0 ? (cents / 100).to_s : format("%.2f", cents / 100.0)
      "$#{dollars}/hr"
    end

    # The brand's web app lives at <subdomain>.<app host> (the mailer's
    # HostValidator uses the same rule). The embed itself is fetched from the
    # bare app host — or, on a dev box, from a tenant host — so strip an
    # already-present tenant prefix instead of doubling it.
    def booking_url(room)
      host = (ENV["HOST"].presence || request.host_with_port).delete_prefix("#{@operator.subdomain}.")
      "#{request.protocol}#{@operator.subdomain}.#{host}/reservations/choose_day?room_id=#{room.id}"
    end
  end
end
