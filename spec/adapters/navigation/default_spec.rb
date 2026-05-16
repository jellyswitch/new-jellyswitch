require "rails_helper"

RSpec.describe Navigation::Default do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  shared_examples "People umbrella in nav" do |role_method|
    it "includes the People top-level item" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).to include("People")
    end

    it "does not include Members & Groups (replaced by People)" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).not_to include("Members & Groups")
    end

    it "does not include Leads as top-level (now under People umbrella)" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).not_to include("Leads")
    end

    it "does not include Automated Emails as top-level" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).not_to include("Automated Emails")
    end

    it "does not include Campaigns as top-level" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).not_to include("Campaigns")
    end

    it "links People at people_path" do
      people = nav.public_send(role_method).find { |i| i[:title] == "People" }
      expect(people[:path]).to eq("/people")
    end
  end

  describe "#admin_nav_items" do
    let(:user) { create(:user, operator: operator, role: User::SUPERADMIN, current_location: location) }
    let(:nav) { described_class.new(operator, location, user) }

    include_examples "People umbrella in nav", :admin_nav_items
  end

  describe "#general_manager_nav_items" do
    let(:user) { create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location) }
    let(:nav) { described_class.new(operator, location, user) }

    include_examples "People umbrella in nav", :general_manager_nav_items
  end

  describe "#community_manager_nav_items" do
    let(:user) { create(:user, operator: operator, role: User::COMMUNITY_MANAGER, current_location: location) }
    let(:nav) { described_class.new(operator, location, user) }

    include_examples "People umbrella in nav", :community_manager_nav_items
  end
end
