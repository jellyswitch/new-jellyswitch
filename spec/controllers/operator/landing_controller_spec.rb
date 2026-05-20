require "rails_helper"

RSpec.describe Operator::LandingController, type: :controller do
  let!(:operator) { create(:operator) }
  let!(:location) { create(:location, operator: operator) }
  let!(:user) { create(:user) }
  let!(:ongoing_reservation) { create(:reservation, user: user, datetime_in: Time.zone.now, minutes: 30) }

  before do
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:current_location).and_return(location)
  end

  describe "#home" do
    it "loads user reservations of the current location only" do
        expect_any_instance_of(User).to receive(:upcoming_or_ongoing_reservation).with(location.id).and_return(ongoing_reservation)
        get :home
        expect(assigns(:reservation)).to eq(ongoing_reservation)
    end
  end

  describe "reserve_now_card partial (regression: unclickable buttons)" do
    # Regression: the previous markup wrapped both <a class='btn btn-block'>
    # buttons inside <p class='card-text'> followed by a stray </p>. WKWebView
    # handled the malformed nesting inconsistently and dropped clicks on the
    # member dashboard. A static-source check is enough — what mattered was
    # the partial's HTML shape, not runtime helper output.
    let(:partial_source) do
      File.read(Rails.root.join("app/views/shared/_reserve_now_card.html.erb"))
    end

    it "wraps the buttons in a <div>, not a <p>" do
      expect(partial_source).to match(%r{<div[^>]*>\s*(?:<%#.*%>\s*)?<%=\s*link_to\s+"Reserve Now"}m)
      expect(partial_source).not_to match(%r{<p[^>]*>\s*<%=\s*link_to\s+"Reserve Now"})
    end

    it "has balanced <p> tags in the rendered output (no stray closing tag)" do
      # Strip ERB comments before counting so explanatory comments mentioning
      # `</p>` don't throw off the tag balance check.
      stripped = partial_source.gsub(/<%#.*?%>/m, "")
      opens = stripped.scan(/<p\b/).size
      closes = stripped.scan(/<\/p>/).size
      expect(opens).to eq(closes)
    end
  end
end
