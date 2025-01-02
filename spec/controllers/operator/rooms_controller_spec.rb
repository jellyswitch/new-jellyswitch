require 'rails_helper'

RSpec.describe Operator::RoomsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:room) { create(:room, operator: operator, location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      room
      get :index
    end

    it "assigns @rooms" do
      expect(assigns(:rooms)).to include(room)
    end

    it "assigns @hidden_rooms" do
      hidden_room = create(:room, operator: operator, location: location, visible: false)
      get :index
      expect(assigns(:hidden_rooms)).to include(hidden_room)
    end

    it "assigns @rentable_rooms" do
      rentable_room = create(:room, operator: operator, location: location, rentable: true)
      get :index
      expect(assigns(:rentable_rooms)).to include(rentable_room)
    end
  end

  describe "GET #show" do
    context "when format is html" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :show, params: { id: room.id }
      end

      it "assigns @room" do
        expect(assigns(:room)).to eq(room)
      end

      it "assigns @reservations" do
        create(:reservation, room: room)
        get :show, params: { id: room.id }
        expect(assigns(:reservations)).to be_present
      end
    end

    context "when format is ics" do
      it "returns calendar data" do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :show, params: { id: room.id, format: :ics }
        expect(response.content_type).to eq("text/calendar")
      end
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :new
    end

    it "assigns a new room" do
      expect(assigns(:room)).to be_a_new(Room)
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        room: {
          name: "New Room",
          description: "Test Description",
          capacity: 4,
          square_footage: 100,
          rentable: true,
          hourly_rate_in_cents: 1000,
          credit_cost: 1,
          visible: true,
          amenities_attributes: [
            { name: "Projector", price: 10, membership_price: 5 }
          ]
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      it "creates a new room" do
        expect {
          post :create, params: valid_params
        }.to change(Room, :count).by(1)
      end

      it "creates associated amenities" do
        expect {
          post :create, params: valid_params
        }.to change(Amenity, :count).by(1)
      end

      context "when add_room_and_add_another is present" do
        it "redirects to new room path" do
          post :create, params: valid_params.merge(add_room_and_add_another: "1")
          expect(response).to redirect_to(new_room_path)
        end
      end

      context "when add_room_and_add_another is not present" do
        it "redirects to room path" do
          post :create, params: valid_params
          expect(response).to redirect_to(room_path(Room.last))
        end
      end
    end

    context "with invalid params" do
      before do
        allow_any_instance_of(Room).to receive(:save).and_return(false)
      end

      it "renders new template" do
        post :create, params: { room: { name: "" } }
        expect(response).to render_template(:new)
      end
    end
  end

  describe "GET #edit" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      get :edit, params: { id: room.id }
    end

    it "assigns @room" do
      expect(assigns(:room)).to eq(room)
    end

    it "builds amenities if none exist" do
      expect(assigns(:room).amenities.first.new_record?).to be true
    end
  end

  describe "PUT #update" do
    let(:update_params) do
      {
        id: room.id,
        room: {
          name: "Updated Room Name",
          amenities_attributes: [
            { name: "New Amenity", price: 15, membership_price: 10 }
          ]
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    context "with valid params" do
      it "updates the room" do
        put :update, params: update_params
        room.reload
        expect(room.name).to eq("Updated Room Name")
      end

      it "handles amenity deletions" do
        amenity = create(:amenity, room: room)
        params = update_params.deep_merge(
          room: {
            amenities_attributes: {
              "0" => { id: amenity.id, _destroy: "1" }
            }
          }
        )
        expect {
          put :update, params: params
        }.to change(Amenity, :count).by(-1)
      end
    end

    context "with invalid params" do
      before do
        allow_any_instance_of(Room).to receive(:update).and_return(false)
      end

      it "redirects to referrer" do
        put :update, params: { id: room.id, room: { name: "" } }
        expect(response).to redirect_to(room_path(room))
      end
    end
  end

  describe "DELETE #destroy" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "destroys the room" do
      room # Create the room
      expect {
        delete :destroy, params: { id: room.id }
      }.to change(Room, :count).by(-1)
    end

    it "redirects to rooms path" do
      delete :destroy, params: { id: room.id }
      expect(response).to redirect_to(rooms_path)
    end
  end

  describe "authorization" do
    context "when user is not authorized" do
      it "restricts access to index" do
        get :index
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to create" do
        post :create, params: { room: { name: "Test" } }
        expect(response).to redirect_to(root_path)
      end

      it "restricts access to edit" do
        get :edit, params: { id: room.id }
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "error handling" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "handles errors in create" do
      allow_any_instance_of(Room).to receive(:save).and_raise("Test error")
      post :create, params: { room: { name: "Test" } }
      expect(flash[:error]).to match(/An error occurred/)
    end

    it "handles errors in update" do
      allow_any_instance_of(Room).to receive(:update).and_raise("Test error")
      put :update, params: { id: room.id, room: { name: "Test" } }
      expect(flash[:error]).to match(/An error occurred/)
    end
  end

  describe "photo handling" do
    let(:photo) { fixture_file_upload('spec/fixtures/test.jpg', 'image/jpeg') }
    let(:photo_params) do
      {
        id: room.id,
        room: {
          photo: photo
        }
      }
    end

    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
    end

    it "allows photo upload" do
      put :update, params: photo_params
      room.reload
      expect(room.photo).to be_attached
    end
  end
end