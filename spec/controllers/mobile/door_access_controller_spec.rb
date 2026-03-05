require 'rails_helper'

RSpec.describe Mobile::DoorAccessController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location1) { create(:location, operator: operator) }
  let(:location2) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, original_location: location1) }

  before do
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #send_user_id_to_ios" do
    before do
      allow(controller).to receive(:current_user).and_return(user)
      allow(controller).to receive(:logged_in?).and_return(true)
    end

    it "does not notify Honeybadger when no location is set" do
      expect(Honeybadger).not_to receive(:notify)

      get :send_user_id_to_ios
    end

    it "renders the send_user_id_to_ios template" do
      allow(Honeybadger).to receive(:notify)

      get :send_user_id_to_ios

      expect(response).to render_template("mobile/door_access/send_user_id_to_ios")
    end
  end
end
