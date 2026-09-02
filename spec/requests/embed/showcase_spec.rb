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
                           featured: true)

    get_widget(products: "day_passes")

    expect(response.body).to include("Coworking Day Pass")
    expect(response.body).to include("$40")
    expect(response.body).to include("180 min meeting room time")
    expect(response.body).to include("Building access during open hours")
    expect(response.body).to include("MOST POPULAR")
    expect(response.body).to include("/embed/concierge/#{operator.subdomain}/checkout")
    # A bare hex override is normalized to CSS form so the buttons actually take the color.
    expect(response.body).to include("#ff5500")
  end

  it "lets the operator's own bullet lines replace the automatic ones" do
    create(:day_pass_type, operator: operator, location: location, name: "Coworking Day Pass",
                           amount_in_cents: 4_000, included_meeting_room_minutes: 180,
                           features: ["Fast wifi", "Free coffee"])

    get_widget(products: "day_passes")

    expect(response.body).to include("Fast wifi")
    expect(response.body).to include("Free coffee")
    expect(response.body).not_to include("180 min meeting room time")
    expect(response.body).not_to include("Building access during open hours")
  end

  it "groups Day Office types with their packs, apart from day passes and theirs" do
    create(:day_pass_type, operator: operator, location: location, name: "Coworking Day Pass", amount_in_cents: 4_000)
    create(:day_pass_type, operator: operator, location: location, name: "Day Office", kind: "day_office", amount_in_cents: 10_000)
    create(:day_pass_type, operator: operator, location: location, name: "5 Pack", quantity: 5, amount_in_cents: 16_000)
    create(:day_pass_type, operator: operator, location: location, name: "Day Office 3 Pack", kind: "day_office", quantity: 3, amount_in_cents: 27_000)

    get_widget(products: "day_passes")

    data = JSON.parse(response.body[/var DATA = (\{.*\});/, 1])
    expect(data["sections"].map { |s| s["key"] }).to eq(%w[day_passes day_offices])
    expect(data["sections"][0]["tiers"].map { |t| t["name"] }).to eq(["Coworking Day Pass", "5 Pack"])
    expect(data["sections"][1]["tiers"].map { |t| t["name"] }).to eq(["Day Office", "Day Office 3 Pack"])
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
                  commitment_interval: 6)

    get_widget(products: "memberships")

    expect(response.body).to include("Resident")
    expect(response.body).to include("$300/month")
    expect(response.body).to include("24/7 building access")
    expect(response.body).to include("6-month minimum commitment")
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
