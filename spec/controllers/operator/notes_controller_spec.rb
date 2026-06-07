require "rails_helper"

RSpec.describe Operator::NotesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", current_location: location) }
  let(:member_user) { create(:user, operator: operator, current_location: location) }
  let(:noted_person) { create(:user, operator: operator, current_location: location, name: "Note Target") }
  let(:organization) { create(:organization, operator: operator) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "POST #create" do
    context "as an admin" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "creates a note on a User" do
        expect {
          post :create, params: { notable_type: "User", notable_id: noted_person.id, note: { body: "Met during tour" } }
        }.to change { noted_person.notes.count }.by(1)
      end

      it "creates a note on an Organization" do
        expect {
          post :create, params: { notable_type: "Organization", notable_id: organization.id, note: { body: "Renewal" } }
        }.to change { organization.notes.count }.by(1)
      end

      it "records the author as current_user" do
        post :create, params: { notable_type: "User", notable_id: noted_person.id, note: { body: "hi" } }
        expect(noted_person.notes.last.author).to eq(admin_user)
      end

      it "rejects an empty body without creating" do
        expect {
          post :create, params: { notable_type: "User", notable_id: noted_person.id, note: { body: "" } }
        }.not_to change { noted_person.notes.count }
      end
    end

    context "as a non-admin member" do
      before { allow(controller).to receive(:current_user).and_return(member_user) }

      it "denies the create (ApplicationController rescues Pundit and redirects)" do
        expect {
          post :create, params: { notable_type: "User", notable_id: noted_person.id, note: { body: "hi" } }
        }.not_to change(Note, :count)
        expect(response).to be_redirect
      end
    end
  end

  describe "DELETE #destroy" do
    let!(:note) { Note.create!(notable: noted_person, operator: operator, author: admin_user, body: "to delete") }

    context "when current_user is the author" do
      before { allow(controller).to receive(:current_user).and_return(admin_user) }

      it "deletes the note" do
        expect { delete :destroy, params: { id: note.id } }.to change { Note.count }.by(-1)
      end
    end

    context "when current_user is a non-admin member" do
      before { allow(controller).to receive(:current_user).and_return(member_user) }

      it "denies the destroy (ApplicationController rescues Pundit and redirects)" do
        expect { delete :destroy, params: { id: note.id } }.not_to change(Note, :count)
        expect(response).to be_redirect
      end
    end
  end
end
