require "test_helper"

class ShowcaseCardTest < ActiveSupport::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
  end

  test "valid with label, http url, and known slot" do
    card = ShowcaseCard.new(operator: @operator, location: @location,
                            label: "Virtual Office", url: "https://vo.example.com", slot: "standalone")
    assert card.valid?
  end

  test "rejects javascript urls and unknown slots" do
    card = ShowcaseCard.new(operator: @operator, location: @location,
                            label: "x", url: "javascript:alert(1)", slot: "sidebar")
    refute card.valid?
    assert card.errors[:url].any?
    assert card.errors[:slot].any?
  end
end
