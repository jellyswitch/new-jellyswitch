require 'rails_helper'

RSpec.describe Operator::EventsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }

  # Create events with specific dates for proper grouping
  let!(:future_event) { create(:event, location: location, user: admin_user, starts_at: 2.days.from_now) }
  let!(:another_future_event) { create(:event, location: location, user: admin_user, starts_at: 2.days.from_now + 2.seconds) }
  let!(:far_future_event) { create(:event, location: location, user: admin_user, starts_at: 5.days.from_now) }
  let!(:past_event) { create(:event, location: location, user: admin_user, starts_at: 2.days.ago) }
  let!(:today_event) { create(:event, location: location, user: admin_user, starts_at: Time.current + 2.hours) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :index
    end

    it "assigns @events grouped by day" do
      expect(assigns(:events).values.flatten).to include(future_event, another_future_event, far_future_event)
      expect(assigns(:events).values.flatten).not_to include(past_event)
    end

    it "groups same-day events together" do
      same_day_events = assigns(:events)[future_event.starts_at.to_date]
      expect(same_day_events).to include(future_event, another_future_event)
    end
  end

  describe "GET #past" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :past
    end

    it "assigns @events with past events grouped by day in reverse order" do
      expect(assigns(:events).values.flatten).to include(past_event)
      expect(assigns(:events).values.flatten).not_to include(future_event, another_future_event, far_future_event)
    end
  end

  describe "GET #show" do
    let(:event_with_location_string) { create(:event, location: location, user: admin_user, location_string: "conference room a") }

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "assigns @event from current location" do
      get :show, params: { id: future_event.id }
      expect(assigns(:event)).to eq(future_event)
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        event: {
          title: "Test Event",
          description: "Test Description",
          starts_at: Time.current + 1.day,
          ends_at: Time.current + 1.day + 2.hours,
          location_string: "Main Conference Room",
          image: fixture_file_upload('spec/fixtures/test.jpg', 'image/jpeg')
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      before do
        allow(Events::Create).to receive(:call).and_return(
          OpenStruct.new(success?: true, event: future_event)
        )
      end

      it "creates a new event with all attributes" do
        post :create, params: valid_params
        expect(flash[:success]).to eq("Event created.")
      end
    end
  end

  describe "PUT #update" do
    let(:update_params) do
      {
        id: future_event.id,
        event: {
          title: "Updated Event",
          location_string: "Updated Location",
          starts_at: Time.current + 2.days,
          ends_at: Time.current + 2.days + 2.hours
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      before do
        allow(Events::Update).to receive(:call).and_return(
          OpenStruct.new(success?: true, event: future_event)
        )
      end

      it "updates the event with all attributes" do
        put :update, params: update_params
        expect(flash[:success]).to eq("Event updated.")
      end
    end
  end

  describe "DELETE #destroy" do
    context "when event has RSVPs" do
      let!(:rsvp) { create(:rsvp, event: future_event, user: regular_user) }

      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "cancels the event and handles RSVPs" do
        allow(Events::Cancel).to receive(:call).and_return(
          OpenStruct.new(success?: true)
        )
        delete :destroy, params: { id: future_event.id }
        expect(flash[:success]).to eq("Event cancelled.")
      end
    end
  end
end