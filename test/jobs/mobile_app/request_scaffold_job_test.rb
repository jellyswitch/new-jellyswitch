require "test_helper"

class MobileApp::RequestScaffoldJobTest < ActiveJob::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    ENV["GITHUB_SCAFFOLD_TOKEN"] = "ghtok"
    @url = "https://api.github.com/repos/jellyswitch/jellyswitch-mobile/actions/workflows/new-brand.yml/dispatches"
  end

  teardown { ENV.delete("GITHUB_SCAFFOLD_TOKEN") }

  test "dispatches the workflow with the operator subdomain" do
    stub = stub_request(:post, @url)
      .with(
        headers: { "Authorization" => "Bearer ghtok" },
        body: { ref: "main", inputs: { subdomain: @operator.subdomain } }.to_json
      )
      .to_return(status: 204)

    MobileApp::RequestScaffoldJob.perform_now(@operator.id)
    assert_requested stub
  end

  test "raises on a non-2xx response so Sidekiq retries" do
    stub_request(:post, @url).to_return(status: 422, body: "nope")
    assert_raises(MobileApp::RequestScaffoldJob::DispatchError) do
      MobileApp::RequestScaffoldJob.perform_now(@operator.id)
    end
  end
end
