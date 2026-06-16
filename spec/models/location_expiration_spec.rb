require "rails_helper"
RSpec.describe "Location#expiration_restricted?" do
  let(:operator) { create(:operator) }
  def loc(state) = create(:location, operator: operator, state: state)
  it { expect(loc("CA").expiration_restricted?).to be(true) }
  it { expect(loc("California").expiration_restricted?).to be(true) }
  it { expect(loc("ca").expiration_restricted?).to be(true) }
  it { expect(loc("NV").expiration_restricted?).to be(false) }
  it { expect(loc("").expiration_restricted?).to be(true) }   # fail-safe
  it { expect(loc(nil).expiration_restricted?).to be(true) }  # fail-safe
end
