require 'rails_helper'

RSpec.describe Operator::MemberFeedbacksController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:member_feedback) { create(:member_feedback, operator: operator, location: location, user: regular_user) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :new
    end

    it "assigns a new member feedback" do
      expect(assigns(:member_feedback)).to be_a_new(MemberFeedback)
    end

    it "authorizes the action" do
      expect(response).to be_successful
    end
  end

  describe "POST #create" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    let(:valid_params) do
      {
        member_feedback: {
          comment: "Great space!",
          rating: 5,
          anonymous: false
        }
      }
    end

    context "with valid params and no existing thread" do
      let(:fresh_feedback) { build(:member_feedback, id: 999, operator: operator, location: location, user: regular_user) }

      before do
        # Make sure the user has zero prior threads so we hit the Create branch.
        # Don't reference `member_feedback` here — its `let` is lazy and would
        # be auto-created by RSpec's mock setup, putting a thread in the DB.
        MemberFeedback.where(user: regular_user).destroy_all
        allow(MemberFeedback::Create).to receive(:call).and_return(
          OpenStruct.new(success?: true, member_feedback: fresh_feedback)
        )
      end

      it "creates a new member feedback thread" do
        post :create, params: valid_params
        expect(MemberFeedback::Create).to have_received(:call)
        expect(flash[:success]).to eq("Thank you — staff will reply right here.")
      end

      it "redirects to the new thread's show page" do
        post :create, params: valid_params
        expect(response).to redirect_to(member_feedback_path(fresh_feedback))
      end
    end

    context "when the member already has a thread for this location" do
      # Regression: each submit used to spawn a fresh MemberFeedback, so
      # staff replies on the old thread were invisible to the member.
      # Submits now append to the existing thread as a FeedbackReply.
      let!(:existing) { create(:member_feedback, operator: operator, location: location, user: regular_user, comment: "First question") }

      it "appends to the existing thread rather than creating a new one" do
        expect(MemberFeedback::Create).not_to receive(:call)
        expect(MemberFeedback::CreateReply).to receive(:call).with(
          hash_including(member_feedback: existing, body: "Great space!")
        ).and_return(OpenStruct.new(success?: true))

        post :create, params: valid_params
      end

      it "redirects to the existing thread's show page after appending" do
        allow(MemberFeedback::CreateReply).to receive(:call).and_return(
          OpenStruct.new(success?: true)
        )

        post :create, params: valid_params
        expect(response).to redirect_to(member_feedback_path(existing))
      end
    end

    context "with invalid params" do
      before do
        allow(MemberFeedback::Create).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Error", member_feedback: MemberFeedback.new)
        )
      end

      it "sets error flash message" do
        post :create, params: valid_params
        expect(flash[:error]).to be_present
      end

      it "renders new template" do
        post :create, params: valid_params
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when an exception occurs" do
      before do
        allow(MemberFeedback::Create).to receive(:call).and_raise("Test error")
      end

      it "handles the error" do
        post :create, params: valid_params
        expect(flash[:error]).to match(/An error occurred/)
      end

      it "redirects to referrer or root" do
        post :create, params: valid_params
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      member_feedback # Create the feedback
      get :index
    end

    it "assigns @member_feedbacks" do
      expect(assigns(:member_feedbacks)).to include(member_feedback)
    end

    it "orders feedbacks by created_at DESC" do
      older_feedback = create(:member_feedback, operator: operator, location: location, user: regular_user, created_at: 2.days.ago)
      newer_feedback = create(:member_feedback, operator: operator, location: location, user: regular_user, created_at: 1.day.ago)

      get :index
      assigned_feedbacks = assigns(:member_feedbacks)
      expect(assigned_feedbacks.index(newer_feedback)).to be < assigned_feedbacks.index(older_feedback)
    end
  end

  describe "GET #show" do
    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
        get :show, params: { id: member_feedback.id }
      end

      it "assigns @member_feedback" do
        expect(assigns(:member_feedback)).to eq(member_feedback)
      end
    end

    context "when user is the feedback owner" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
        get :show, params: { id: member_feedback.id }
      end

      it "allows access to their own feedback" do
        expect(response).to be_successful
      end
    end

    context "when user is not admin and not the owner" do
      let(:other_user) { create(:user, operator: operator, original_location: location) }

      before do
        allow(controller).to receive(:current_user).and_return(other_user)
        get :show, params: { id: member_feedback.id }
      end

      it "redirects to root path" do
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe "authorization" do
    context "when user is not authorized" do
      before do
        allow(controller).to receive(:current_user).and_return(regular_user)
      end

      it "cannot access index" do
        get :index
        expect(response).to redirect_to(root_path)
      end

      it "cannot access show for other user's feedback" do
        other_feedback = create(:member_feedback, operator: operator, location: location, user: create(:user))
        get :show, params: { id: other_feedback.id }
        expect(response).to redirect_to(root_path)
      end
    end

    context "when user is admin" do
      before do
        allow(controller).to receive(:current_user).and_return(admin_user)
      end

      it "can access index" do
        get :index
        expect(response).to be_successful
      end

      it "can access show for any feedback" do
        get :show, params: { id: member_feedback.id }
        expect(response).to be_successful
      end
    end
  end
end