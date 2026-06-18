require "rails_helper"

# The scripted Concierge's brain: map a stated need to the operator's REAL
# catalog. Product-backed options only appear if the operator actually offers
# them; admin-handled options are always present (capture-only).
RSpec.describe Concierge::Recommender do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  def options(loc = location)
    described_class.new(operator: operator, location: loc).options
  end

  def option(intent, loc = location)
    options(loc).find { |o| o[:intent] == intent }
  end

  it "recommends the cheapest single day pass from the real catalog" do
    create(:day_pass_type, operator: operator, location: location, name: "Premium", quantity: 1, amount_in_cents: 4_000)
    create(:day_pass_type, operator: operator, location: location, name: "Standard", quantity: 1, amount_in_cents: 2_500)

    opt = option("day_pass")
    expect(opt[:self_serve]).to be true
    expect(opt[:product][:name]).to eq("Standard")
    expect(opt[:product][:price_cents]).to eq(2_500)
  end

  it "offers a bundle only when a quantity>1 day pass type exists" do
    expect(option("day_pass_bundle")).to be_nil
    create(:day_pass_type, operator: operator, location: location, name: "5-Pack", quantity: 5, amount_in_cents: 10_000)
    expect(option("day_pass_bundle")[:product][:quantity]).to eq(5)
  end

  it "offers membership only when an individual plan exists" do
    expect(option("membership")).to be_nil
    create(:plan, operator: operator, location: location, plan_type: "individual",
                  name: "Resident", amount_in_cents: 20_000, available: true, visible: true)
    expect(option("membership")[:product][:name]).to eq("Resident")
  end

  it "always includes the admin-handled options (capture-only)" do
    %w[day_office conference_room office question].each do |intent|
      opt = option(intent)
      expect(opt).to be_present
      expect(opt[:self_serve]).to be false
      expect(opt[:product]).to be_nil
    end
  end

  it "excludes products from a different location" do
    other = create(:location, operator: operator)
    create(:day_pass_type, operator: operator, location: other, quantity: 1, amount_in_cents: 2_500)
    expect(option("day_pass")).to be_nil
  end

  it "skips invisible/unavailable products" do
    create(:day_pass_type, operator: operator, location: location, quantity: 1, amount_in_cents: 2_500, visible: false)
    expect(option("day_pass")).to be_nil
  end
end
