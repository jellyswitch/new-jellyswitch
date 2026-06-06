require "rails_helper"

RSpec.describe Operator::OfficerndImportsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "superadmin", original_location: location, current_location: location) }
  let(:csv)      { fixture_file_upload("spec/fixtures/officernd_members.csv", "text/csv") }

  before do
    request.host = "#{operator.subdomain}.lvh.me" # activates the tenant via the subdomain filter
    request.headers["X-Operator-Subdomain"] = operator.subdomain
    ActsAsTenant.current_tenant = operator
    allow(controller).to receive(:current_user).and_return(admin)
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_tenant).and_return(operator)
  end

  describe "GET #new" do
    it "renders the upload form" do
      get :new
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST #create" do
    it "stores the CSV, detects headers/columns, and advances to the map step" do
      expect {
        post :create, params: { kind: "members", csv: csv }
      }.to change(OfficerndImport, :count).by(1)

      import = OfficerndImport.last
      expect(import.headers).to include("Email Address", "Full Name")
      expect(import.column_mapping["email"]).to eq("Email Address")
      expect(import.column_mapping["name"]).to eq("Full Name")
      expect(import.row_count).to eq(2)
      expect(response).to redirect_to(map_officernd_import_path(import))
    end

    it "re-renders with an error when no file is chosen" do
      post :create, params: { kind: "members" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "the mapping → preview → commit flow" do
    let(:import) do
      i = operator.officernd_imports.create!(kind: "members", location_id: location.id)
      i.csv.attach(csv) # persisted record → blob uploads immediately, downloadable below
      i.update!(
        headers: i.parsed.headers,
        row_count: i.parsed.row_count,
        column_mapping: i.detect_column_mapping(i.parsed.headers),
      )
      i
    end

    it "GET #map renders" do
      get :map, params: { id: import.id }
      expect(response).to have_http_status(:ok)
    end

    it "PATCH #update_mapping advances (to sort, since memberships are present)" do
      patch :update_mapping, params: { id: import.id,
        column_mapping: { email: "Email Address", name: "Full Name", membership: "Membership" } }
      expect(response).to redirect_to(sort_officernd_import_path(import))
    end

    it "GET #preview builds a dry-run preview without writing" do
      import.update!(column_mapping: { "email" => "Email Address", "name" => "Full Name" })
      expect {
        get :preview, params: { id: import.id }
      }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
      expect(assigns(:preview)[:total_rows]).to eq(2)
    end

    it "POST #commit imports the members and marks the import committed" do
      import.update!(column_mapping: { "email" => "Email Address", "name" => "Full Name" })
      expect {
        post :commit, params: { id: import.id }
      }.to change { operator.users.where("email in (?)", %w[ada@example.com grace@example.com]).count }.by(2)

      expect(import.reload.status).to eq("committed")
      expect(response).to render_template(:result)
    end
  end
end
