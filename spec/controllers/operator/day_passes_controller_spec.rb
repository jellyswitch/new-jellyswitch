require 'rails_helper'

RSpec.describe Operator::DayPassesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  # A realistic customer-facing paid pass. (The factory defaults amount_in_cents
  # to 0, but a $0 type can't be self-purchased — see the purchase-guard specs.)
  let(:day_pass_type) { create(:day_pass_type, operator: operator, location: location, amount_in_cents: 5000) }
  let(:day_pass) { create(:day_pass, operator: operator, location: location, user: regular_user, day_pass_type: day_pass_type) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  describe "GET #index" do
    before do
      allow(controller).to receive(:current_user).and_return(admin_user)
      day_pass
      get :index
    end

    it "assigns @day_passes" do
      expect(assigns(:day_passes)).to include(day_pass)
    end
  end

  describe "GET #new" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when day pass type is specified" do
      before { get :new, params: { day_pass_type_id: day_pass_type.id } }

      it "assigns @day_pass" do
        expect(assigns(:day_pass)).to be_a_new(DayPass)
      end

      it "assigns @day_pass_type" do
        expect(assigns(:day_pass_type)).to eq(day_pass_type)
      end

      it "includes stripe" do
        expect(assigns(:include_stripe)).to be true
      end
    end
  end

  describe "POST #create" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    let(:valid_params) do
      {
        day_pass: {
          # Not Date.current: the stubbed result's `day_pass` let-row already
          # holds today for this buyer, and plain-string day params are now
          # parsed (daily-limit hardening), so posting the same day would
          # correctly land on the duplicate-purchase interstitial — which has
          # its own coverage. These specs are about the purchase itself.
          day: Date.current + 2,
          day_pass_type: day_pass_type.id
        }
      }
    end

    context "with stripe token" do
      let(:stripe_token) { "tok_visa" }

      context "when successful" do
        before do
          allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_return(
            OpenStruct.new(success?: true, day_pass: day_pass)
          )
        end

        it "creates a day pass" do
          post :create, params: valid_params.merge(stripeToken: stripe_token)
          expect(flash[:success]).to match(/Welcome/)
        end

        it "redirects to home path" do
          post :create, params: valid_params.merge(stripeToken: stripe_token)
          expect(response).to redirect_to(home_path)
        end
      end

      context "when unsuccessful" do
        before do
          allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_return(
            OpenStruct.new(success?: false, message: "Error", day_pass: DayPass.new)
          )
        end

        it "sets error flash message" do
          post :create, params: valid_params.merge(stripeToken: stripe_token)
          expect(flash[:error]).to be_present
        end
      end
    end

    context "when an exception occurs" do
      before do
        allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_raise("Test error")
      end

      it "handles the error" do
        post :create, params: valid_params
        expect(flash[:error]).to match(/An error occurred/)
      end
    end

    # Members may only self-purchase an available, paid type — mirrors the
    # mobile API guardrails. A crafted POST can pass any operator-scoped id.
    context "when the date is outside the purchase window" do
      it "rejects a wrong-year date without charging (the year-dropdown mis-tap)" do
        expect(DayPassInteractorFactory).not_to receive(:for)

        post :create, params: {
          day_pass: { day: (Date.current + 1.year).to_s, day_pass_type: day_pass_type.id },
          stripeToken: "tok_visa",
        }

        expect(flash[:error]).to include("double-check the date")
      end

      it "rejects a past date without charging" do
        expect(DayPassInteractorFactory).not_to receive(:for)

        post :create, params: {
          day_pass: { day: (Date.current - 2).to_s, day_pass_type: day_pass_type.id },
          stripeToken: "tok_visa",
        }

        expect(flash[:error]).to include("already passed")
      end
    end

    context "when the type is free ($0)" do
      let(:free_type) { create(:day_pass_type, operator: operator, location: location, amount_in_cents: 0) }

      it "rejects the purchase (no free self-mint = free access)" do
        expect(DayPassInteractorFactory).not_to receive(:for)
        post :create, params: { day_pass: { day: Date.current, day_pass_type: free_type.id } }
        expect(flash[:error]).to match(/free day passes/i)
      end
    end

    context "when the type is retired (available: false)" do
      let(:retired_type) { create(:day_pass_type, operator: operator, location: location, amount_in_cents: 5000, available: false) }

      it "rejects the purchase of a pulled SKU" do
        expect(DayPassInteractorFactory).not_to receive(:for)
        post :create, params: { day_pass: { day: Date.current, day_pass_type: retired_type.id } }
        expect(flash[:error]).to match(/not available/i)
      end
    end

    context "when a free bundle SKU is submitted" do
      let(:free_bundle) { create(:day_pass_type, operator: operator, location: location, quantity: 2, amount_in_cents: 0) }

      it "rejects it before the bundle flow" do
        expect(Billing::DayPassBundles::CreateBundle).not_to receive(:call)
        post :create, params: { day_pass: { day: Date.current, day_pass_type: free_bundle.id } }
        expect(flash[:error]).to match(/free day passes/i)
      end
    end

    # Hidden (visible:false) types are unlocked by an access code. The redeem_paid
    # checkout threads that code into the purchase POST (as discount_code). A
    # direct POST without the matching code must not buy a hidden pass at its
    # unlisted rate — mirrors the mobile API guard.
    context "with a hidden (visible: false) day pass type" do
      let(:hidden_type) do
        create(:day_pass_type, operator: operator, location: location,
               amount_in_cents: 1000, visible: false, code: "CAFE")
      end

      it "purchases when the matching access code is present (redeem flow)" do
        allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_return(
          OpenStruct.new(success?: true, day_pass: day_pass)
        )
        # Date.current + 2, not today: the stub's `day_pass` let-row holds today
        # for this buyer, and a same-day plain-string POST now correctly lands
        # on the duplicate-purchase interstitial (daily-limit hardening).
        post :create, params: {
          day_pass: { day: Date.current + 2, day_pass_type: hidden_type.id },
          discount_code: "CAFE",
        }
        expect(flash[:error]).to be_blank
        expect(flash[:success]).to be_present
      end

      it "does not bounce the matching-code purchase back to the redeem page" do
        allow(DayPassInteractorFactory).to receive_message_chain(:for, :call).and_return(
          OpenStruct.new(success?: true, day_pass: day_pass)
        )
        # Date.current + 2, not today: the stub's `day_pass` let-row holds today
        # for this buyer, and a same-day plain-string POST now correctly lands
        # on the duplicate-purchase interstitial (daily-limit hardening).
        post :create, params: {
          day_pass: { day: Date.current + 2, day_pass_type: hidden_type.id },
          discount_code: "CAFE",
        }
        expect(response).not_to redirect_to(
          redeem_paid_day_passes_path(code: "CAFE", day_pass_type_id: hidden_type.id)
        )
      end

      it "rejects a direct purchase with no access code" do
        expect(DayPassInteractorFactory).not_to receive(:for)
        post :create, params: { day_pass: { day: Date.current, day_pass_type: hidden_type.id } }
        expect(flash[:error]).to match(/not available/i)
        expect(response).to redirect_to(new_day_pass_path)
      end

      it "rejects a direct purchase carrying a non-matching code" do
        expect(DayPassInteractorFactory).not_to receive(:for)
        post :create, params: {
          day_pass: { day: Date.current, day_pass_type: hidden_type.id },
          discount_code: "WRONGCODE",
        }
        expect(flash[:error]).to match(/not available/i)
        expect(response).to redirect_to(new_day_pass_path)
      end

      it "rejects using a DIFFERENT hidden pass's code to unlock this one" do
        create(:day_pass_type, operator: operator, location: location,
               amount_in_cents: 2000, visible: false, code: "OTHER")
        expect(DayPassInteractorFactory).not_to receive(:for)
        post :create, params: {
          day_pass: { day: Date.current, day_pass_type: hidden_type.id },
          discount_code: "OTHER",
        }
        expect(flash[:error]).to match(/not available/i)
        expect(response).to redirect_to(new_day_pass_path)
      end
    end
  end

  describe "POST #create with an N-Pack (bundle) day pass type" do
    let(:bundle_type) do
      create(:day_pass_type, operator: operator, location: location, quantity: 2, amount_in_cents: 7000)
    end
    let(:bundle_params) do
      { day_pass: { day: Date.current, day_pass_type: bundle_type.id } }
    end
    let(:bundle_result) do
      OpenStruct.new(
        success?: true,
        day_pass_bundle: OpenStruct.new(id: 1, passes_remaining: 2, day_pass_type: bundle_type),
      )
    end

    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "with a stripe token" do
      it "routes to the bundle flow, NOT the single day-pass factory" do
        expect(DayPassInteractorFactory).not_to receive(:for)
        expect(Billing::DayPassBundles::UpdatePaymentAndCreateBundle)
          .to receive(:call).and_return(bundle_result)
        post :create, params: bundle_params.merge(stripeToken: "tok_visa")
      end

      it "does not mint a single dated day pass" do
        allow(Billing::DayPassBundles::UpdatePaymentAndCreateBundle).to receive(:call).and_return(bundle_result)
        expect { post :create, params: bundle_params.merge(stripeToken: "tok_visa") }
          .not_to change(DayPass, :count)
      end

      it "shows a passes-added success message" do
        allow(Billing::DayPassBundles::UpdatePaymentAndCreateBundle).to receive(:call).and_return(bundle_result)
        post :create, params: bundle_params.merge(stripeToken: "tok_visa")
        expect(flash[:success]).to match(/passes added/i)
      end
    end

    context "without a token (customer already on file)" do
      it "uses CreateBundle" do
        expect(Billing::DayPassBundles::CreateBundle).to receive(:call).and_return(bundle_result)
        post :create, params: bundle_params
      end
    end

    context "with a discount code" do
      it "rejects it and does not create a bundle" do
        expect(Billing::DayPassBundles::CreateBundle).not_to receive(:call)
        expect(Billing::DayPassBundles::UpdatePaymentAndCreateBundle).not_to receive(:call)
        post :create, params: bundle_params.merge(discount_code: "SAVE10")
        expect(flash[:error]).to match(/can't be applied/i)
        expect(response).to redirect_to(new_day_pass_path(day_pass_type_id: bundle_type.id))
      end
    end

    # A hidden (code-gated) bundle reached via the redeem flow carries its own
    # access code as discount_code. That's the access key, not a coupon — the
    # bundle purchase must still go through, not get rejected as "can't apply".
    context "when the bundle is hidden and its access code is threaded in" do
      let(:hidden_bundle) do
        create(:day_pass_type, operator: operator, location: location,
               quantity: 2, amount_in_cents: 7000, visible: false, code: "NPACK")
      end

      it "creates the bundle instead of rejecting the access code" do
        expect(Billing::DayPassBundles::CreateBundle).to receive(:call).and_return(bundle_result)
        post :create, params: {
          day_pass: { day: Date.current, day_pass_type: hidden_bundle.id },
          discount_code: "NPACK",
        }
        expect(flash[:error]).to be_blank
      end
    end
  end

  describe "GET #code" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
      get :code
    end

    it "authorizes the action" do
      expect(response).to be_successful
    end
  end

  describe "POST #redeem_code" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when code redemption is successful" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: true, day_pass_type: day_pass_type, day_pass_type_id: day_pass_type.id)
        )
      end

      context "when day pass type is free" do
        before do
          allow(day_pass_type).to receive(:free?).and_return(true)
          allow(Billing::DayPasses::RedeemFreeDayPass).to receive(:call).and_return(
            OpenStruct.new(success?: true)
          )
        end

        it "redeems the free day pass" do
          post :redeem_code, params: { code: "TEST123" }
          expect(flash[:success]).to eq("Day Pass redeemed!")
        end

        it "redirects to home path" do
          post :redeem_code, params: { code: "TEST123" }
          expect(response).to redirect_to(home_path)
        end
      end

      context "when day pass type is paid" do
        before do
          allow(day_pass_type).to receive(:free?).and_return(false)
        end

        it "redirects to redeem paid path" do
          post :redeem_code, params: { code: "TEST123" }
          expect(response).to redirect_to(redeem_paid_day_passes_path(code: "TEST123", day_pass_type_id: day_pass_type.id))
        end
      end
    end

    context "when code redemption fails" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Invalid code")
        )
      end

      it "sets error flash message" do
        post :redeem_code, params: { code: "INVALID" }
        expect(flash[:error]).to be_present
      end

      it "redirects to code path" do
        post :redeem_code, params: { code: "INVALID" }
        expect(response).to redirect_to(code_day_passes_path)
      end
    end
  end

  describe "GET #redeem_paid" do
    before do
      allow(controller).to receive(:current_user).and_return(regular_user)
    end

    context "when code is valid" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: true, day_pass_type: day_pass_type)
        )
        get :redeem_paid, params: { code: "TEST123" }
      end

      it "assigns @day_pass_type" do
        expect(assigns(:day_pass_type)).to eq(day_pass_type)
      end

      it "assigns @day_pass" do
        expect(assigns(:day_pass)).to be_a_new(DayPass)
      end

      it "assigns @access_code so the checkout POST can carry it" do
        expect(assigns(:access_code)).to eq("TEST123")
      end

      it "includes stripe" do
        expect(assigns(:include_stripe)).to be true
      end
    end

    context "when code is invalid" do
      before do
        allow(Billing::DayPasses::RedeemCode).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "No such code")
        )
        get :redeem_paid, params: { code: "INVALID" }
      end

      it "sets error flash message" do
        expect(flash[:error]).to eq("No such code.")
      end

      it "redirects to code path" do
        expect(response).to redirect_to(code_day_passes_path)
      end
    end
  end
end