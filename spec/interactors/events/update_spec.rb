require 'rails_helper'

RSpec.describe Events::Update do
  let(:user) { create(:user) }
  let(:location) { create(:location, time_zone: "Pacific Time (US & Canada)") }
  let(:event) { create(:event, user: user, location: location, starts_at: Time.current) }

  def run(event, starts_at_str, ends_at_str = nil)
    params = ActionController::Parameters.new(
      title: event.title,
      starts_at: starts_at_str,
      ends_at: ends_at_str
    ).permit!

    Events::Update.call(event: event, event_params: params, user: user, location: location)
  end

  describe "timezone handling across DST boundary" do
    context "updating event to a post-DST date" do
      it "stores the correct UTC time with PDT offset" do
        result = run(event, "03/15/2026 3:00 PM")

        expect(result).to be_a_success
        event.reload
        # 3:00 PM PDT = 10:00 PM UTC
        expect(event.starts_at.utc.hour).to eq(22)

        displayed = event.starts_at.in_time_zone("Pacific Time (US & Canada)")
        expect(displayed.hour).to eq(15)
      end
    end

    context "updating event to a pre-DST date" do
      it "stores the correct UTC time with PST offset" do
        result = run(event, "03/06/2026 3:00 PM")

        expect(result).to be_a_success
        event.reload
        # 3:00 PM PST = 11:00 PM UTC
        expect(event.starts_at.utc.hour).to eq(23)

        displayed = event.starts_at.in_time_zone("Pacific Time (US & Canada)")
        expect(displayed.hour).to eq(15)
      end
    end
  end
end
