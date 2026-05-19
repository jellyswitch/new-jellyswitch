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

    it "renders email_opened as a simple action label, never the subject" do
      # UX decision: the user already knows which email was opened (the
      # adjacent Sent row says it) — surfacing the subject again was just
      # noise, especially when fallback lookups failed and it surfaced as
      # "(no subject)".
      opened = Activity.create!(
        user: user, operator: operator,
        kind: "email_opened",
        subject: user,
        occurred_at: send_time + 5.seconds,
        payload: { "sg_event_id" => "abc123" },
      )

      expect(helper.activity_label(opened)).to eq("Opened email")
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
  end

  describe "#activity_label for payment_succeeded" do
    let(:operator) { create(:operator) }
    let(:user) { create(:user, operator: operator) }

    it "uses amount_paid when populated" do
      paid = Activity.create!(
        user: user, operator: operator,
        kind: "payment_succeeded",
        subject: user,
        occurred_at: Time.current,
        payload: { "amount_due" => 4000, "amount_paid" => 4000, "status" => "paid" },
      )

      expect(helper.activity_label(paid)).to eq("Paid $40.00")
    end

    it "falls back to amount_due when amount_paid is zero" do
      # Reproduces Christine Crook's $40 day pass that surfaced as $0.00.
      # Invoice#amount_paid is only synced on the Stripe webhook path;
      # direct PaymentIntent captures (day passes, room reservations)
      # leave it at 0 even after status='paid'.
      paid = Activity.create!(
        user: user, operator: operator,
        kind: "payment_succeeded",
        subject: user,
        occurred_at: Time.current,
        payload: { "amount_due" => 4000, "amount_paid" => 0, "status" => "paid" },
      )

      expect(helper.activity_label(paid)).to eq("Paid $40.00")
    end
  end
end
