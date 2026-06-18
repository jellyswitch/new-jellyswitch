require "rails_helper"

RSpec.describe "Embed::Concierge capture", type: :request do
  let(:operator) { create(:operator, concierge_enabled: true) }
  let!(:location) { create(:location, operator: operator, visible: true) }

  # These exercise capture logic, not the shared /embed/* rate limit.
  around do |example|
    was = Rack::Attack.enabled
    Rack::Attack.enabled = false
    example.run
    Rack::Attack.enabled = was
  end

  def capture(params)
    post "/embed/concierge/#{operator.subdomain}/capture", params: params
  end

  let(:base) { { email: "Jo@Example.com ", name: "Jo Visitor", location_id: location.id } }

  it "captures a Person + a chat Activity with the intent/transcript payload" do
    expect {
      capture(base.merge(intent: "day_pass", recommended_product: "Day Pass",
                         transcript: ["hi", "need a desk today"]))
    }.to change(User, :count).by(1).and change { Activity.where(kind: "chat").count }.by(1)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["ok"]).to be true
    expect(body["self_serve"]).to be true

    user = User.find_by("lower(email) = ?", "jo@example.com")
    expect(user).to be_present
    expect(user.operator).to eq(operator)
    activity = Activity.where(kind: "chat", user: user).first
    expect(activity.payload["intent"]).to eq("day_pass")
    expect(activity.payload["transcript"]).to eq(["hi", "need a desk today"])
    expect(activity.subject).to eq(location)
  end

  it "does NOT create feedback for a self-serve (checkout) intent" do
    expect {
      capture(base.merge(intent: "membership"))
    }.not_to change(MemberFeedback, :count)
    expect(JSON.parse(response.body)["self_serve"]).to be true
  end

  it "routes a question into the Feedback channel (MemberFeedback) and alerts staff" do
    expect {
      capture(base.merge(intent: "question", message: "Do you have parking?"))
    }.to change(MemberFeedback, :count).by(1)
      .and have_enqueued_job(SendNotificationsJob).with(an_instance_of(MemberFeedback))

    fb = MemberFeedback.last
    expect(fb.comment).to eq("Do you have parking?")
    expect(fb.user.email).to eq("jo@example.com")
    expect(JSON.parse(response.body)["self_serve"]).to be false
  end

  it "routes a room request to feedback with a labeled comment" do
    capture(base.merge(intent: "conference_room", message: "Friday 2pm for 6?"))
    expect(MemberFeedback.last.comment).to eq("Conference room request: Friday 2pm for 6?")
  end

  it "reuses an existing Person instead of duplicating" do
    existing = create(:user, operator: operator, email: "jo@example.com", role: "unassigned")
    expect { capture(base.merge(intent: "day_pass")) }.not_to change(User, :count)
    expect(Activity.where(kind: "chat", user: existing).count).to eq(1)
  end

  it "honors an explicit marketing opt-out on a new lead" do
    capture(base.merge(intent: "day_pass", marketing_opt_in: "false"))
    expect(User.find_by("lower(email) = ?", "jo@example.com").email_opted_out).to be true
  end

  it "silently drops a honeypot submission" do
    expect { capture(base.merge(intent: "day_pass", _hp: "bot")) }.not_to change(User, :count)
    expect(response).to have_http_status(:ok)
  end

  it "requires an email" do
    capture(name: "No Email", intent: "day_pass", location_id: location.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to eq("email_required")
  end

  it "404s when the Concierge is not enabled" do
    operator.update!(concierge_enabled: false)
    capture(base.merge(intent: "day_pass"))
    expect(response).to have_http_status(:not_found)
  end
end
