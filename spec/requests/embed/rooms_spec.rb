require "rails_helper"

RSpec.describe "Embed::Rooms", type: :request do
  let(:operator)  { create(:operator, conference_rooms_enabled: true) }
  let!(:location) { create(:location, operator: operator, visible: true) }

  def make_room(attrs = {})
    create(:room, { operator: operator, location: location, rentable: true, visible: true,
                    hourly_rate_in_cents: 5000, capacity: 8, square_footage: 240 }.merge(attrs))
  end

  def get_widget(params = {})
    get "/embed/rooms/#{operator.subdomain}", params: params
  end

  it "serves a no-op when disabled" do
    operator.update!(conference_rooms_enabled: false)
    get_widget
    expect(response.body).to include("not enabled")
    expect(response.body).not_to include("jsw-rm")
  end

  it "renders for a settings-page preview token even while disabled, uncached" do
    operator.update!(conference_rooms_enabled: false)
    make_room(name: "Preview Room")

    get_widget(preview_token: Embed::RoomsController.preview_token_for(operator))

    expect(response.body).to include("jsw-rm")
    expect(response.body).to include("Preview Room")
    expect(response.headers["Cache-Control"]).to include("no-cache")
  end

  it "ignores a forged preview token" do
    operator.update!(conference_rooms_enabled: false)
    get_widget(preview_token: "not-a-token")
    expect(response.body).to include("not enabled")
  end

  it "caches public traffic for one minute so room edits show up fast" do
    get_widget
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("max-age=60, public")
  end

  it "lists a rentable room with seats, rate, description, features, and a Book now link into the brand's wizard" do
    room = make_room(name: "Summit Room", description: "Lake views, big table",
                     features: ["Whiteboard", "Video conferencing"])
    Amenity.create!(room: room, name: "Coffee service", price: 0, membership_price: 0)
    Amenity.create!(room: room, name: "Catering", price: 40, membership_price: 30)

    get_widget

    data = JSON.parse(response.body[/var DATA = (\{.*?\});\n/m, 1])
    card = data["rooms"].find { |r| r["name"] == "Summit Room" }
    expect(card).to include("capacity" => 8, "square_footage" => 240, "rate_label" => "$50/hr",
                            "description" => "Lake views, big table")
    # Typed features first, then the room's free amenities; paid add-ons are not features.
    expect(card["bullets"]).to eq(["Whiteboard", "Video conferencing", "Coffee service"])
    expect(card["book_url"]).to eq("http://#{operator.subdomain}.www.example.com/reservations/choose_day?room_id=#{room.id}")
    expect(data["accent"]).to eq(operator.embed_accent_color)
    expect(data["button"]).to eq(operator.embed_button_color)
  end

  it "labels a $0 room by what covers it instead of a price" do
    make_room(name: "Call Room", hourly_rate_in_cents: 0, include_with_day_pass: true)
    make_room(name: "Members Room", hourly_rate_in_cents: 0, include_with_day_pass: false)
    make_room(name: "Odd Cents", hourly_rate_in_cents: 1250)
    get_widget
    data = JSON.parse(response.body[/var DATA = (\{.*?\});\n/m, 1])
    labels = data["rooms"].to_h { |r| [r["name"], r["rate_label"]] }
    expect(labels).to include("Call Room" => "Included with a day pass",
                              "Members Room" => "Included with membership",
                              "Odd Cents" => "$12.50/hr")
  end

  it "does not prefix the tenant twice when the embed is fetched from a tenant host" do
    room = make_room
    get "/embed/rooms/#{operator.subdomain}", headers: { "Host" => "#{operator.subdomain}.www.example.com" }
    expect(response.body).to include("http://#{operator.subdomain}.www.example.com/reservations/choose_day?room_id=#{room.id}")
    expect(response.body).not_to include("#{operator.subdomain}.#{operator.subdomain}.")
  end

  it "lists only rentable, visible, active rooms at the pinned location" do
    make_room(name: "Bookable")
    make_room(name: "Members Only", rentable: false)
    make_room(name: "Hidden", visible: false)
    make_room(name: "Retired", archived: true)
    other = create(:location, operator: operator, visible: true)
    make_room(name: "Elsewhere", location: other)

    get_widget(location_id: location.id)

    expect(response.body).to include("Bookable")
    %w[Members\ Only Hidden Retired Elsewhere].each { |n| expect(response.body).not_to include(n) }
  end

  it "renders the empty state when no room is open for booking" do
    get_widget
    expect(response.body).to include("No rooms are open for booking")
  end

  it "nudges the embedder to pin a location at a multi-location operator" do
    create(:location, operator: operator, visible: true)
    get_widget
    expect(response.body).to include("Conference Rooms setup")
    expect(response.body).to include("location_id=#{location.id}")
  end
end
