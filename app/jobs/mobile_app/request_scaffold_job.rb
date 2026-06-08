module MobileApp
  # Triggers the mobile repo's new-brand GitHub Action for an operator's
  # subdomain. The Action runs the scaffolder and opens a PR (build/submit stay
  # developer-driven). Token comes from ENV or Rails credentials.
  class RequestScaffoldJob < ApplicationJob
    queue_as :default

    class DispatchError < StandardError; end

    REPO = "jellyswitch/jellyswitch-mobile".freeze
    WORKFLOW = "new-brand.yml".freeze

    def perform(operator_id)
      operator = ActsAsTenant.without_tenant { Operator.find_by(id: operator_id) }
      return unless operator

      response = HTTParty.post(
        "https://api.github.com/repos/#{REPO}/actions/workflows/#{WORKFLOW}/dispatches",
        headers: {
          "Authorization" => "Bearer #{github_token}",
          "Accept" => "application/vnd.github+json",
          "X-GitHub-Api-Version" => "2022-11-28",
          "User-Agent" => "jellyswitch-backend"
        },
        body: { ref: "main", inputs: { subdomain: operator.subdomain } }.to_json,
        timeout: 15
      )

      return if response.code.between?(200, 299)

      raise DispatchError, "workflow_dispatch failed (#{response.code}): #{response.body}"
    end

    private

    def github_token
      ENV["GITHUB_SCAFFOLD_TOKEN"].presence ||
        Rails.application.credentials.dig(:github, :scaffold_token)
    end
  end
end
