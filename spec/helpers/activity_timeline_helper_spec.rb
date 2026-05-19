require "rails_helper"

RSpec.describe ActivityTimelineHelper, type: :helper do
  let(:operator) { create(:operator) }
  let(:user) { create(:user, operator: operator) }

  describe "#activity_label for engagement events" do
    let(:send_time) { Time.current }

    let!(:email_sent) do
      Activity.create!(
        user: user, operator: operator,
        kind: "email_sent",
        subject: user,
        occurred_at: send_time,
        payload: { "subject" => "Welcome! Here's what you need to know" },
      )
    end

    it "renders the email_sent subject directly from its own payload" do
      expect(helper.activity_label(email_sent)).to eq("Sent: Welcome! Here's what you need to know")
    end

    it "falls back to the prior email_sent subject for email_opened without a subject" do
      opened = Activity.create!(
        user: user, operator: operator,
        kind: "email_opened",
        subject: user,
        occurred_at: send_time + 5.seconds,
        payload: { "sg_event_id" => "abc123" },
      )

      expect(helper.activity_label(opened)).to eq("Opened: Welcome! Here's what you need to know")
    end

    it "falls back to the prior email_sent subject for email_clicked without a subject" do
      clicked = Activity.create!(
        user: user, operator: operator,
        kind: "email_clicked",
        subject: user,
        occurred_at: send_time + 10.seconds,
        payload: { "sg_event_id" => "xyz789", "url" => "https://example.com" },
      )

      expect(helper.activity_label(clicked)).to eq("Clicked: Welcome! Here's what you need to know")
    end

    it "uses the engagement event's own subject if present" do
      opened = Activity.create!(
        user: user, operator: operator,
        kind: "email_opened",
        subject: user,
        occurred_at: send_time + 5.seconds,
        payload: { "subject" => "Different subject" },
      )

      expect(helper.activity_label(opened)).to eq("Opened: Different subject")
    end

    it "shows (no subject) when no prior email_sent exists within 60 days" do
      orphan_user = create(:user, operator: operator)
      opened = Activity.create!(
        user: orphan_user, operator: operator,
        kind: "email_opened",
        subject: orphan_user,
        occurred_at: send_time,
        payload: { "sg_event_id" => "noprior" },
      )

      expect(helper.activity_label(opened)).to eq("Opened: (no subject)")
    end

    it "does not match a send older than 60 days" do
      old_user = create(:user, operator: operator)
      Activity.create!(
        user: old_user, operator: operator,
        kind: "email_sent",
        subject: old_user,
        occurred_at: send_time - 61.days,
        payload: { "subject" => "Ancient newsletter" },
      )
      opened = Activity.create!(
        user: old_user, operator: operator,
        kind: "email_opened",
        subject: old_user,
        occurred_at: send_time,
        payload: { "sg_event_id" => "outofwindow" },
      )

      expect(helper.activity_label(opened)).to eq("Opened: (no subject)")
    end

    it "picks the most recent send when multiple exist before the open" do
      Activity.create!(
        user: user, operator: operator,
        kind: "email_sent",
        subject: user,
        occurred_at: send_time + 1.hour,
        payload: { "subject" => "Newer send" },
      )
      opened = Activity.create!(
        user: user, operator: operator,
        kind: "email_opened",
        subject: user,
        occurred_at: send_time + 1.hour + 5.seconds,
        payload: { "sg_event_id" => "afternewer" },
      )

      expect(helper.activity_label(opened)).to eq("Opened: Newer send")
    end
  end
end
