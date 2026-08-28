require "rails_helper"

RSpec.describe "Embed::Showcase", type: :request do
  let(:operator)  { create(:operator, showcase_enabled: true, embed_accent_override: "ff5500") }
  let!(:location) { create(:location, operator: operator, visible: true) }

  def get_widget(params = {})
    get "/embed/showcase/#{operator.subdomain}", params: params
  end

  it "serves a no-op when the Showcase is disabled" do
    operator.update!(showcase_enabled: false)
    get_widget
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("not enabled")
    expect(response.body).not_to include("jsw-sc")
  end

  it "renders day-pass tiers with derived bullets, features, price, and checkout CTA" do
    create(:day_pass_type, operator: operator, location: location, name: "Coworking Day Pass",
                           quantity: 1, amount_in_cents: 4_000, included_meeting_room_minutes: 180,
                           features: ["Free coffee"], featured: true)

    get_widget(products: "day_passes")

    expect(response.body).to include("Coworking Day Pass")
    expect(response.body).to include("$40")
    expect(response.body).to include("180 min meeting room time")
    expect(response.body).to include("Free coffee")
    expect(response.body).to include("MOST POPULAR")
    expect(response.body).to include("/embed/concierge/#{operator.subdomain}/checkout")
    expect(response.body).to include("ff5500")
  end

  it "emits JSON-LD Product offers for purchasable tiers" do
    create(:day_pass_type, operator: operator, location: location, name: "Day Pass", amount_in_cents: 4_000)
    get_widget(products: "day_passes")
    expect(response.body).to include("application/ld+json")
    expect(response.body).to include("amount_in_cents") # cents reach the payload; JS formats the Offer price
  end

  it "renders membership tiers with commitment and access bullets" do
    create(:plan, operator: operator, location_id: location.id, name: "Resident",
                  amount_in_cents: 30_000, building_access_level: :all_hours,
                  commitment_interval: 6, features: ["Mail service"])

    get_widget(products: "memberships")

    expect(response.body).to include("Resident")
    expect(response.body).to include("$300/month")
    expect(response.body).to include("24/7 building access")
    expect(response.body).to include("6-month minimum commitment")
    expect(response.body).to include("Mail service")
  end

  it "renders the setup nudge when unpinned at a multi-location operator" do
    other = create(:location, operator: operator, visible: true, name: "Fulton")
    create(:day_pass_type, operator: operator, location: location, name: "Zephyr Pass", amount_in_cents: 4_000)

    get_widget(products: "day_passes")

    expect(response.body).to include("multiple locations")
    expect(response.body).to include("location_id=#{other.id}")
    expect(response.body).not_to include("Zephyr Pass")
  end

  it "renders the pinned location's catalog at a multi-location operator" do
    fulton = create(:location, operator: operator, visible: true, name: "Fulton")
    create(:day_pass_type, operator: operator, location: location, name: "Zephyr Pass", amount_in_cents: 4_000)
    create(:day_pass_type, operator: operator, location: fulton, name: "Fulton Pass", amount_in_cents: 3_500)

    get_widget(products: "day_passes", location_id: fulton.id)

    expect(response.body).to include("Fulton Pass")
    expect(response.body).not_to include("Zephyr Pass")
  end

  it "renders standalone link-out cards with the outbound URL and no JSON-LD" do
    ShowcaseCard.create!(operator: operator, location: location, label: "Virtual Office",
                         price_text: "From $49/mo", url: "https://vo.example.com", slot: "standalone")

    get_widget(products: "cards")

    expect(response.body).to include("Virtual Office")
    expect(response.body).to include("https://vo.example.com")
    expect(response.body).to include("From $49/mo")
    # Card tiers carry kind "card" and no amount — the runtime JSON-LD builder
    # skips them (someone else's service is not ours to mark up).
    expect(response.body).to include('\"kind\":\"card\"').or include('"kind":"card"')
  end

  it "hides invisible products" do
    create(:day_pass_type, operator: operator, location: location, name: "Hidden Pass",
                           amount_in_cents: 4_000, visible: false)
    get_widget(products: "day_passes")
    expect(response.body).not_to include("Hidden Pass")
  end
end
