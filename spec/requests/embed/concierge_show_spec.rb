require "rails_helper"

RSpec.describe "Embed::Concierge show", type: :request do
  let(:operator)  { create(:operator, concierge_enabled: true, primary_color: "112233") }
  let!(:location) { create(:location, operator: operator, visible: true) }

  it "renders the widget with the real catalog and inherited theming when active" do
    create(:day_pass_type, operator: operator, location: location, name: "Coworking Day Pass",
                           quantity: 1, amount_in_cents: 2_500)

    get "/embed/concierge/#{operator.subdomain}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What brings you in today")
    expect(response.body).to include("Coworking Day Pass") # catalog-driven option
    expect(response.body).to include("My team needs to meet") # admin-handled option
    expect(response.body).to include("--cx-primary: 112233")  # inherited brand color
    expect(response.headers["X-Frame-Options"]).to eq("ALLOWALL")
  end

  it "404s when not active and there's no preview token" do
    operator.update!(concierge_enabled: false)
    get "/embed/concierge/#{operator.subdomain}"
    expect(response).to have_http_status(:not_found)
  end

  it "renders the disabled widget for a valid admin preview token" do
    operator.update!(concierge_enabled: false)
    token = Embed::ConciergeController.verifier.generate(
      { "operator_id" => operator.id, "exp" => 1.hour.from_now.to_i }
    )
    get "/embed/concierge/#{operator.subdomain}", params: { preview_token: token }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("not live yet")
  end
end
