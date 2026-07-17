require "rails_helper"
require "rake"

RSpec.describe "staging:scrub_stripe_secrets rake task" do
  before do
    Rake.application = Rake::Application.new
    # `load` (not rake_require) so the tasks re-register in each example's
    # fresh Rake application — rake_require tracks loaded files globally.
    load Rails.root.join("lib/tasks/staging.rake")
    Rake::Task.define_task(:environment) # no-op; the app is already loaded
  end

  let(:operator) do
    create(:operator, stripe_user_id: "acct_op", stripe_access_token: "sk_live_secret",
           stripe_refresh_token: "rt_live", stripe_publishable_key: "pk_live_op")
  end
  let!(:location) do
    create(:location, operator: operator, stripe_user_id: "acct_loc",
           stripe_access_token: "sk_live_secret", stripe_refresh_token: "rt_live",
           stripe_publishable_key: "pk_live_loc")
  end

  def stripe_config(secret_key)
    { secret_key: secret_key, test_secret_key: "sk_test_x",
      publishable_key: "pk_x", test_publishable_key: "pk_test_x" }
  end

  it "nulls the OAuth secret columns but keeps stripe_user_id" do
    allow(Rails.configuration).to receive(:stripe).and_return(stripe_config("sk_test_abc"))

    Rake::Task["staging:scrub_stripe_secrets"].invoke

    location.reload
    expect(location.stripe_access_token).to be_nil
    expect(location.stripe_refresh_token).to be_nil
    expect(location[:stripe_publishable_key]).to be_nil
    expect(location.stripe_user_id).to eq("acct_loc")

    operator.reload
    expect(operator.stripe_access_token).to be_nil
    expect(operator.stripe_user_id).to eq("acct_op")
  end

  it "refuses to run when STRIPE_SECRET_KEY is a live key" do
    allow(Rails.configuration).to receive(:stripe).and_return(stripe_config("sk_live_abc"))

    expect { Rake::Task["staging:scrub_stripe_secrets"].invoke }
      .to raise_error(SystemExit)

    expect(location.reload.stripe_access_token).to eq("sk_live_secret")
  end
end
