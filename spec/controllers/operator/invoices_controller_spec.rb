require 'rails_helper'

RSpec.describe Operator::InvoicesController, type: :controller do
  let(:operator) { create(:operator, billing_state: "production") }
  let(:location) { create(:location, operator: operator) }
  let(:admin_user) { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:regular_user) { create(:user, operator: operator, original_location: location) }
  let(:organization) { create(:organization, operator: operator, location: location, stripe_customer_id: "cus_123") }
  let(:invoice) { create(:invoice, operator: operator, location: location, billable: organization) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    request.host = "#{operator.subdomain}.lvh.me"
    allow(controller).to receive(:current_user).and_return(admin_user)
  end

  describe "GET #index" do
    before { get :index }

    it "assigns @invoices with pagination" do
      expect(assigns(:invoices)).to include(invoice)
      expect(assigns(:pagy)).to be_present
    end

    it "assigns @title" do
      expect(assigns(:title)).to eq("All Invoices")
    end

    it "renders generic template" do
      expect(response).to render_template(:generic)
    end
  end

  describe "GET #recent" do
    let!(:recent_invoice) { create(:invoice, operator: operator, location: location, date: 15.days.ago) }
    let!(:old_invoice) { create(:invoice, operator: operator, location: location, date: 45.days.ago) }

    before { get :recent }

    it "assigns @invoices with recent invoices" do
      expect(assigns(:invoices)).to include(recent_invoice)
      expect(assigns(:invoices)).not_to include(old_invoice)
    end

    it "assigns @title" do
      expect(assigns(:title)).to eq("Recent Invoices")
    end
  end

  describe "GET #delinquent" do
    let!(:delinquent_invoice) { create(:invoice, operator: operator, location: location, status: "open", due_date: 1.day.ago) }
    let!(:current_invoice) { create(:invoice, operator: operator, location: location, status: "open", due_date: 1.day.from_now) }

    before { get :delinquent }

    it "assigns @invoices with delinquent invoices" do
      expect(assigns(:invoices)).to include(delinquent_invoice)
      expect(assigns(:invoices)).not_to include(current_invoice)
    end

    it "assigns @title" do
      expect(assigns(:title)).to eq("Delinquent Invoices")
    end
  end

  describe "GET #groups" do
    let!(:user_invoice) { create(:invoice, operator: operator, location: location, billable: regular_user) }

    before { get :groups }

    it "assigns @invoices with group invoices" do
      expect(assigns(:invoices)).to include(invoice)
      expect(assigns(:invoices)).not_to include(user_invoice)
    end

    it "assigns @title" do
      expect(assigns(:title)).to eq("Group Invoices")
    end
  end

  describe "GET #open" do
    let!(:open_invoice) { create(:invoice, operator: operator, location: location, status: "open") }
    let!(:paid_invoice) { create(:invoice, operator: operator, location: location, status: "paid") }

    before { get :open }

    it "assigns @invoices with open invoices" do
      expect(assigns(:invoices)).to include(open_invoice)
      expect(assigns(:invoices)).not_to include(paid_invoice)
    end

    it "assigns @title" do
      expect(assigns(:title)).to eq("Open Invoices")
    end
  end

  describe "POST #charge" do
    context "when charge succeeds" do
      before do
        allow(Billing::Invoices::ChargeInvoice).to receive(:call).and_return(
          OpenStruct.new(success?: true)
        )
        allow_any_instance_of(Organization).to receive(:has_billing_for_location?).and_return(true)
        post :charge, params: { invoice_id: invoice.id }
      end

      it "sets success flash message" do
        expect(flash[:success]).to eq("Charge succeeded.")
      end
    end

    context "when charge fails" do
      before do
        allow(Billing::Invoices::ChargeInvoice).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Error charging invoice")
        )
        allow_any_instance_of(Organization).to receive(:has_billing_for_location?).and_return(true)
        post :charge, params: { invoice_id: invoice.id }
      end

      it "sets error flash message" do
        expect(flash[:error]).to be_present
      end
    end
  end

  describe "GET #new" do
    context "with user_id parameter" do
      before { get :new, params: { user_id: regular_user.id } }

      it "assigns @billable as user" do
        expect(assigns(:billable)).to eq(regular_user)
      end

      it "assigns @invoice" do
        expect(assigns(:invoice)).to be_a_new(Invoice)
      end
    end

    context "with organization_id parameter" do
      before { get :new, params: { organization_id: organization.id } }

      it "assigns @billable as organization" do
        expect(assigns(:billable)).to eq(organization)
      end
    end

    context "without billable parameters" do
      before { get :new }

      it "sets error flash message" do
        expect(flash[:error]).to be_present
      end

      it "redirects to invoices path" do
        expect(response).to redirect_to(invoices_path)
      end
    end
  end

  describe "POST #create" do
    context "with valid user billable" do
      let(:valid_params) do
        {
          billable_type: "User",
          billable_id: regular_user.id,
          amount: 1000,
          description: "Test invoice"
        }
      end

      before do
        allow(Billing::Invoices::Custom::Create).to receive(:call).and_return(
          OpenStruct.new(success?: true)
        )
      end

      it "creates invoice and redirects to user path" do
        post :create, params: valid_params
        expect(flash[:success]).to eq("Invoice created.")
        expect(response).to redirect_to(user_path(regular_user))
      end
    end

    context "with valid organization billable" do
      let(:valid_params) do
        {
          billable_type: "Organization",
          billable_id: organization.id,
          amount: 1000,
          description: "Test invoice"
        }
      end

      before do
        allow(Billing::Invoices::Custom::Create).to receive(:call).and_return(
          OpenStruct.new(success?: true)
        )
      end

      it "creates invoice and redirects to organization path" do
        post :create, params: valid_params
        expect(flash[:success]).to eq("Invoice created.")
        expect(response).to redirect_to(organization_path(organization))
      end
    end

    context "with invalid params" do
      before do
        allow(Billing::Invoices::Custom::Create).to receive(:call).and_return(
          OpenStruct.new(success?: false, message: "Error creating invoice")
        )
      end

      it "renders new template" do
        post :create, params: { billable_type: "User", billable_id: regular_user.id }
        expect(response).to render_template(:new)
      end
    end

    context "with invalid billable" do
      it "sets error flash and redirects to root" do
        post :create, params: { billable_type: "Invalid", billable_id: 999 }
        expect(flash[:error]).to be_present
        expect(response).to redirect_to(root_path)
      end
    end
  end
end