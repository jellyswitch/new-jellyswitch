require "rails_helper"

RSpec.describe ConciergeConversation do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  it "auto-generates a unique session token on create" do
    convo = ConciergeConversation.create!(operator: operator, location: location)
    expect(convo.session_token).to be_present
    expect(convo.status).to eq("open")
  end

  describe "#awaiting_staff_timeout?" do
    let(:convo) do
      ConciergeConversation.create!(operator: operator, location: location,
                                    last_visitor_message_at: 6.minutes.ago)
    end

    it "is true when open and no staff reply within the SLA window" do
      expect(convo.awaiting_staff_timeout?).to be true
    end

    it "is false once a staffer has replied" do
      convo.update!(last_staff_message_at: 1.minute.ago)
      expect(convo.awaiting_staff_timeout?).to be false
    end

    it "is false within the SLA window" do
      convo.update!(last_visitor_message_at: 1.minute.ago)
      expect(convo.awaiting_staff_timeout?).to be false
    end
  end
end

RSpec.describe Location, "#open_now?" do
  let(:operator) { create(:operator) }
  let(:location) do
    create(:location, operator: operator, time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "09:00", working_day_end: "18:00")
  end

  def at_pacific(hour, min = 0)
    ActiveSupport::TimeZone["Pacific Time (US & Canada)"].local(2026, 6, 18, hour, min)
  end

  it "is open during posted hours and closed outside them" do
    expect(location.open_now?(at_pacific(10))).to be true
    expect(location.open_now?(at_pacific(8, 59))).to be false
    expect(location.open_now?(at_pacific(18))).to be false # end-exclusive
    expect(location.open_now?(at_pacific(23))).to be false
  end

  it "does not raise on a malformed working time (defensive default)" do
    location.update_column(:working_day_start, "9am") # bypass normalizer
    expect { location.open_now?(at_pacific(10)) }.not_to raise_error
  end
end
