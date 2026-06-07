require "rails_helper"

RSpec.describe Navigation::Default do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  shared_examples "People umbrella in nav" do |role_method|
    it "includes the People top-level item" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).to include("People (CRM)")
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
      people = nav.public_send(role_method).find { |i| i[:title] == "People (CRM)" }
      expect(people[:path]).to eq("/people")
    end

    it "includes the Groups top-level item" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      expect(titles).to include("Groups")
    end

    it "links Groups at organizations_path" do
      groups = nav.public_send(role_method).find { |i| i[:title] == "Groups" }
      expect(groups[:path]).to eq("/organizations")
    end

    it "places Groups immediately after the People item" do
      titles = nav.public_send(role_method).map { |i| i[:title] }
      people_idx = titles.index { |t| t.to_s.start_with?("People") }
      expect(titles[people_idx + 1]).to eq("Groups")
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
