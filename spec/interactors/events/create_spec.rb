require 'rails_helper'

RSpec.describe Events::Create do
  let(:user) { create(:user) }
  let(:location) { create(:location, time_zone: "Pacific Time (US & Canada)") }

  def run(starts_at_str, ends_at_str = nil)
    params = ActionController::Parameters.new(
      title: "Test Event",
      description: "A test",
      starts_at: starts_at_str,
      ends_at: ends_at_str
    ).permit!

    Events::Create.call(event_params: params, user: user, location: location)
  end

  describe "timezone handling across DST boundary" do
    # PST (UTC-8) is in effect before March 8, 2026
    # PDT (UTC-7) is in effect after March 8, 2026

    context "event scheduled before DST (in PST)" do
      it "stores the correct UTC time with PST offset (-08:00)" do
        result = run("03/06/2026 2:00 PM")

        expect(result).to be_a_success
        event = result.event
        # 2:00 PM PST = 10:00 PM UTC
        expect(event.starts_at.utc.hour).to eq(22)
        expect(event.starts_at.utc.day).to eq(6)
      end
    end

    context "event scheduled after DST (in PDT)" do
      it "stores the correct UTC time with PDT offset (-07:00)" do
        result = run("03/15/2026 2:00 PM")

        expect(result).to be_a_success
        event = result.event
        # 2:00 PM PDT = 9:00 PM UTC
        expect(event.starts_at.utc.hour).to eq(21)
        expect(event.starts_at.utc.day).to eq(15)
      end
    end

    context "event scheduled on DST transition day" do
      it "stores the correct UTC time for the afternoon after spring-forward" do
        result = run("03/08/2026 2:00 PM")

        expect(result).to be_a_success
        event = result.event
        # 2:00 PM PDT (DST in effect by afternoon) = 9:00 PM UTC
        expect(event.starts_at.utc.hour).to eq(21)
        expect(event.starts_at.utc.day).to eq(8)
      end
    end

    context "event with ends_at across DST" do
      it "stores both starts_at and ends_at with correct offsets" do
        result = run("03/15/2026 2:00 PM", "03/15/2026 4:00 PM")

        expect(result).to be_a_success
        event = result.event
        # 2:00 PM PDT = 9:00 PM UTC
        expect(event.starts_at.utc.hour).to eq(21)
        # 4:00 PM PDT = 11:00 PM UTC
        expect(event.ends_at.utc.hour).to eq(23)
      end
    end

    context "displays correct local time after round-trip" do
      it "shows the same local time that was entered for a post-DST event" do
        result = run("03/15/2026 2:00 PM")
        event = result.event

        displayed_time = event.starts_at.in_time_zone("Pacific Time (US & Canada)")
        expect(displayed_time.hour).to eq(14)
        expect(displayed_time.min).to eq(0)
      end

      it "shows the same local time that was entered for a pre-DST event" do
        result = run("03/06/2026 2:00 PM")
        event = result.event

        displayed_time = event.starts_at.in_time_zone("Pacific Time (US & Canada)")
        expect(displayed_time.hour).to eq(14)
        expect(displayed_time.min).to eq(0)
      end
    end
  end

  describe "Eastern timezone across DST" do
    let(:location) { create(:location, time_zone: "Eastern Time (US & Canada)") }

    it "handles EST correctly before DST" do
      result = run("03/06/2026 2:00 PM")
      event = result.event

      # 2:00 PM EST = 7:00 PM UTC
      expect(event.starts_at.utc.hour).to eq(19)
      displayed = event.starts_at.in_time_zone("Eastern Time (US & Canada)")
      expect(displayed.hour).to eq(14)
    end

    it "handles EDT correctly after DST" do
      result = run("03/15/2026 2:00 PM")
      event = result.event

      # 2:00 PM EDT = 6:00 PM UTC
      expect(event.starts_at.utc.hour).to eq(18)
      displayed = event.starts_at.in_time_zone("Eastern Time (US & Canada)")
      expect(displayed.hour).to eq(14)
    end
  end

  describe "validation" do
    it "fails when starts_at is missing" do
      result = run(nil)
      expect(result).to be_a_failure
      expect(result.message).to eq("You must provide a start date for your event.")
    end
  end
end
