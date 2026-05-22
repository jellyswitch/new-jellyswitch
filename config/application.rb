
require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

require "view_component/engine"

module Jellyswitch
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Autoload paths
    config.eager_load_paths << "#{config.root}/lib"
    config.autoload_paths << "#{config.root}/lib"

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
    config.time_zone = ENV['TIME_ZONE'] || "Pacific Time (US & Canada)"

    # Background jobs
    config.active_job.queue_adapter = :sidekiq


    config.action_mailer.default_url_options = { host: ENV['HOST'] }
    config.action_view.form_with_generates_remote_forms = true
    config.action_mailer.preview_paths = ["#{Rails.root}/test/mailers"]

    config.action_controller.asset_host = ENV['ASSET_HOST']
    config.beginning_of_week = :sunday
    config.hosts.clear

    # Rack 3+ raises EmptyContentError when a request has
    # Content-Type: multipart/form-data but an empty body. Pre-Rack-3 this
    # was silently treated as empty params. In production this only fires
    # from bots and vulnerability scanners POSTing junk to "/" — no browser
    # produces it. Map it to 400 so the client gets a proper Bad Request
    # instead of 500, and suppress it from Honeybadger in
    # config/initializers/honeybadger.rb.
    config.action_dispatch.rescue_responses["Rack::Multipart::EmptyContentError"] = :bad_request
  end
end
