require "rails_helper"

RSpec.describe "Embed::OfficeInventory", type: :request do
  let(:operator)  { create(:operator, office_inventory_enabled: true) }
  let!(:location) { create(:location, operator: operator, visible: true) }

  def make_office(attrs = {})
    Office.create!({ operator: operator, location: location, name: "Office #{rand(1000)}",
                     capacity: 4, square_footage: 150, visible: true }.merge(attrs))
  end

  def get_widget(params = {})
    get "/embed/office_inventory/#{operator.subdomain}", params: params
  end

  it "serves a no-op when disabled" do
    operator.update!(office_inventory_enabled: false)
    get_widget
    expect(response.body).to include("not enabled")
    expect(response.body).not_to include("jsw-oi")
  end

  it "renders for a settings-page preview token even while disabled, uncached" do
    operator.update!(office_inventory_enabled: false)
    make_office(name: "Preview Office")

    get_widget(preview_token: Embed::OfficeInventoryController.preview_token_for(operator))

    expect(response.body).to include("jsw-oi")
    expect(response.body).to include("Preview Office")
    expect(response.headers["Cache-Control"]).to include("no-cache")
  end

  it "ignores a forged preview token" do
    operator.update!(office_inventory_enabled: false)
    get_widget(preview_token: "not-a-token")
    expect(response.body).to include("not enabled")
  end

  it "lists a vacant office with rate, size, and Available now" do
    make_office(name: "Office 12", asking_rate_in_cents: 110_000, description: "Corner light")
    get_widget

    expect(response.body).to include("Office 12")
    expect(response.body).to include("$1100/mo")
    expect(response.body).to include("Available now")
    expect(response.body).to include("Corner light")
  end

  it "shows Contact for pricing when no asking rate" do
    make_office
    get_widget
    expect(response.body).to include("Contact for pricing")
  end

  it "hides a leased office unless staff flag it coming available" do
    leased = make_office(name: "Leased Office")
    create(:office_lease, operator: operator, office: leased, location: location,
                          start_date: 1.month.ago, end_date: 3.months.from_now)
    get_widget
    expect(response.body).not_to include("Leased Office")

    leased.update!(coming_available: true)
    get "/embed/office_inventory/#{operator.subdomain}" # fresh request, no cache in test
    expect(response.body).to include("Leased Office")
    expect(response.body).to include("Available from #{3.months.from_now.strftime('%b %-d, %Y')}")
  end

  it "hides invisible offices" do
    make_office(name: "Hidden Office", visible: false)
    get_widget
    expect(response.body).not_to include("Hidden Office")
  end

  it "renders the empty-state when everything is taken" do
    get_widget
    expect(response.body).to include("spoken for")
  end

  describe "POST inquiry" do
    let!(:office) { make_office(name: "Office 7", asking_rate_in_cents: 90_000) }
    let(:url) { "/embed/office_inventory/#{operator.subdomain}/inquiries" }

    it "creates the Person, files feedback to the location, tags office interest, and redirects" do
      expect {
        post url, params: { office_id: office.id, location_id: location.id,
                            name: "Olive Ostrom", email: "olive@example.com",
                            message: "Team of 3, October move-in" }
      }.to change(User, :count).by(1).and change(MemberFeedback, :count).by(1)

      expect(response).to redirect_to(%r{/embed/office_inventory/#{operator.subdomain}/thank_you})
      user = User.find_by(email: "olive@example.com", operator: operator)
      feedback = MemberFeedback.last
      expect(feedback.user).to eq(user)
      expect(feedback.location).to eq(location)
      expect(feedback.comment).to include("Office 7")
      expect(feedback.comment).to include("asking $900/mo")
      expect(feedback.comment).to include("Team of 3, October move-in")
      expect(InterestTag.find_by(user_id: user.id, product: "office")).to be_present
    end

    it "reuses an existing Person by email" do
      existing = create(:user, operator: operator, email: "back@example.com")
      expect {
        post url, params: { office_id: office.id, location_id: location.id,
                            name: "Someone Else", email: "back@example.com" }
      }.not_to change(User, :count)
      expect(MemberFeedback.last.user).to eq(existing)
    end

    it "silently drops honeypot submissions" do
      expect {
        post url, params: { office_id: office.id, location_id: location.id,
                            name: "Bot", email: "bot@example.com", _hp: "gotcha" }
      }.not_to change(MemberFeedback, :count)
      expect(response).to have_http_status(:ok)
    end

    it "rejects an office from another operator's location" do
      foreign_loc = create(:location, operator: create(:operator))
      expect {
        post url, params: { office_id: office.id, location_id: foreign_loc.id,
                            name: "X", email: "x@example.com" }
      }.not_to change(MemberFeedback, :count)
    end
  end
end
