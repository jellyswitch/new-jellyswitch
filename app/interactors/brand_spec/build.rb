module BrandSpec
  # Operator (+ already-resolved asset URLs) -> canonical brand-spec hash.
  # URLs are passed in because Active Storage URL generation needs the request
  # host, which lives in the controller (or the CI job), not here.
  class Build
    include Interactor

    delegate :operator, :app_icon_url, :wordmark_url, to: :context

    def call
      op = operator
      key = op.subdomain.parameterize
      bundle = "com.jellyswitch.#{key.delete('-')}"

      context.brand_spec = {
        key: key,
        name: op.name,
        subdomain: op.subdomain,
        apiBase: "https://#{op.subdomain}.jellyswitch.com/api/v1",
        bundleId: { ios: bundle, android: bundle },
        colors: { primary: op.primary_color, accent: op.accent_color },
        splashBackground: "#FFFFFF",
        assets: { appIcon: app_icon_url, wordmark: wordmark_url }
      }
    end
  end
end
