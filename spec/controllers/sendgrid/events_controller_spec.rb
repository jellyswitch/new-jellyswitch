require "rails_helper"

RSpec.describe Sendgrid::EventsController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, current_location: location, email: "kim@example.com") }

  # Sendgrid webhook payloads — minimal but realistic.
  def event(kind, overrides = {})
    {
      "email" => user.email,
      "event" => kind,
      "timestamp" => Time.current.to_i,
      "sg_event_id" => SecureRandom.uuid,
      "sg_message_id" => "msg_#{SecureRandom.hex(8)}",
      "smtp-id" => "<#{SecureRandom.hex(8)}@sendgrid.net>",
    }.merge(overrides)
  end

  def post_events(events)
    request.env["RAW_POST_DATA"] = events.to_json
    request.env["CONTENT_TYPE"] = "application/json"
    post :receive, body: events.to_json
  end

  describe "POST #receive" do
    it "returns 200 on a well-formed payload" do
      post_events([event("open")])
      expect(response).to have_http_status(:ok)
    end

    it "returns 400 on invalid JSON" do
      request.env["CONTENT_TYPE"] = "application/json"
      post :receive, body: "{not-json"
      expect(response).to have_http_status(:bad_request)
    end

    context "open events" do
      it "writes an email_opened Activity for the matching user" do
        user # touch let to create
        expect {
          post_events([event("open", "subject" => "Welcome!")])
        }.to change { Activity.where(user: user, kind: "email_opened").count }.by(1)
        activity = Activity.where(user: user, kind: "email_opened").last
        expect(activity.payload["subject"]).to eq("Welcome!")
      end

      it "marks open=true on matching CampaignSends" do
        campaign = Campaign.create!(operator: operator, name: "X",
                                    campaign_type: "single", status: "active", segment: {})
        step = CampaignStep.create!(campaign: campaign, position: 0, subject: "S", body: "B")
        send_row = CampaignSend.create!(campaign: campaign, campaign_step: step,
                                        user: user, status: "sent", sent_at: 1.day.ago)
        post_events([event("open")])
        expect(send_row.reload.opened).to be true
        expect(send_row.opened_at).not_to be_nil
      end
    end

    context "click events" do
      it "writes an email_clicked Activity with the URL in payload" do
        user
        expect {
          post_events([event("click", "url" => "https://example.com/path")])
        }.to change { Activity.where(user: user, kind: "email_clicked").count }.by(1)
        expect(Activity.where(user: user, kind: "email_clicked").last.payload["url"]).to eq("https://example.com/path")
      end
    end

    context "bounce / dropped events" do
      it "flips User.email_bounced = true" do
        user
        post_events([event("bounce")])
        expect(user.reload.email_bounced).to be true
      end

      it "treats dropped the same as bounce" do
        user
        post_events([event("dropped")])
        expect(user.reload.email_bounced).to be true
      end
    end

    context "spamreport events" do
      it "flips User.email_opted_out = true" do
        user
        post_events([event("spamreport")])
        expect(user.reload.email_opted_out).to be true
      end
    end

    context "unknown email" do
      it "silently ignores events for emails with no matching User" do
        user # eager-create so the signup Activity isn't counted by the expect block
        expect {
          post_events([event("open", "email" => "stranger@example.com")])
        }.not_to change { Activity.count }
        expect(response).to have_http_status(:ok)
      end
    end

    context "batch payload" do
      it "processes multiple events in one POST" do
        user
        expect {
          post_events([event("open"), event("click"), event("bounce")])
        }.to change { Activity.where(user: user).count }.by(2) # open + click; bounce flips a flag
          .and change { user.reload.email_bounced }.from(false).to(true)
      end
    end

    context "HTTP Basic auth" do
      before do
        @prev_user = ENV["SENDGRID_WEBHOOK_USERNAME"]
        @prev_pass = ENV["SENDGRID_WEBHOOK_PASSWORD"]
        ENV["SENDGRID_WEBHOOK_USERNAME"] = "sg"
        ENV["SENDGRID_WEBHOOK_PASSWORD"] = "secret"
      end
      after do
        ENV["SENDGRID_WEBHOOK_USERNAME"] = @prev_user
        ENV["SENDGRID_WEBHOOK_PASSWORD"] = @prev_pass
      end

      it "returns 401 when credentials are missing" do
        post_events([event("open")])
        expect(response).to have_http_status(:unauthorized)
      end

      it "returns 200 when credentials are correct" do
        request.env["HTTP_AUTHORIZATION"] = ActionController::HttpAuthentication::Basic.encode_credentials("sg", "secret")
        post_events([event("open")])
        expect(response).to have_http_status(:ok)
      end

      it "returns 401 when credentials are wrong" do
        request.env["HTTP_AUTHORIZATION"] = ActionController::HttpAuthentication::Basic.encode_credentials("sg", "WRONG")
        post_events([event("open")])
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "wiring engagement events into the Person timeline (Phase 7.2)" do
    before { user }

    it "appears on the Person's Emails timeline group after the corresponding email_sent" do
      sent_at = 1.hour.ago
      Activity.create!(user: user, operator: operator, kind: "email_sent",
                       occurred_at: sent_at, subject: user,
                       payload: { "subject" => "Welcome!" })
      post_events([event("open", "subject" => "Welcome!", "timestamp" => Time.current.to_i)])
      opened = Activity.where(user: user, kind: "email_opened").last
      sent = Activity.where(user: user, kind: "email_sent").last
      expect(opened).to be_present
      expect(opened.occurred_at).to be > sent.occurred_at

      emails_tab_kinds = ActivityTimelineHelper::KIND_GROUPS["emails"]
      timeline = user.activities.where(kind: emails_tab_kinds).order(occurred_at: :desc)
      # Reverse-chronological: the open appears above the send
      expect(timeline.map(&:kind).take(2)).to eq(["email_opened", "email_sent"])
    end

    it "renders a friendly label for engagement activities" do
      Activity.create!(user: user, operator: operator, kind: "email_opened",
                       occurred_at: 1.minute.ago, subject: user,
                       payload: { "subject" => "Hello there" })
      label = ApplicationController.helpers.activity_label(Activity.where(user: user, kind: "email_opened").last)
      expect(label).to eq("Opened: Hello there")
    end
  end
end
