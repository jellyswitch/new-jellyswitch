require "rails_helper"

RSpec.describe Operator::ProductEmailTemplatesController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "superadmin", original_location: location, current_location: location) }

  before do
    request.host = "#{operator.subdomain}.lvh.me"
    request.headers["X-Operator-Subdomain"] = operator.subdomain
    ActsAsTenant.current_tenant = operator
    allow(controller).to receive(:require_authentication).and_return(true)
    allow(controller).to receive(:current_user).and_return(admin)
    allow(controller).to receive(:current_tenant).and_return(operator)
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:background_image)
  end

  def template_for(product_type, email_type)
    t = ProductEmailTemplate.find_or_initialize_by(
      operator: operator, location: location, product_type: product_type, email_type: email_type
    )
    t.subject ||= "S"
    t.save!(validate: false) unless t.persisted?
    t
  end

  describe "POST #copy_from_day_pass" do
    it "copies the Day Pass body into the matching bundle template" do
      day_pass = template_for("day_pass", "onboarding")
      day_pass.update!(body: "<p>Day pass copy for {{date}}</p>")
      bundle = template_for("day_pass_bundle", "onboarding")

      post :copy_from_day_pass, params: { id: bundle.id }

      expect(bundle.reload.body.to_s).to include("Day pass copy")
      expect(flash[:success]).to be_present
    end

    it "flags (and leaves the body unchanged) when there's no Day Pass template to copy from" do
      bundle = template_for("day_pass_bundle", "onboarding")
      bundle.update!(body: "<p>BUNDLE_STARTER</p>")
      ProductEmailTemplate.where(operator: operator, product_type: "day_pass", email_type: "onboarding").destroy_all

      post :copy_from_day_pass, params: { id: bundle.id }

      expect(bundle.reload.body.to_s).to include("BUNDLE_STARTER")
      expect(flash[:error]).to be_present
    end

    it "refuses to prefill the replenishment email (no Day Pass counterpart)" do
      replen = template_for("day_pass_bundle", "replenishment")

      post :copy_from_day_pass, params: { id: replen.id }

      expect(flash[:error]).to match(/onboarding and follow-up/i)
    end
  end
end
