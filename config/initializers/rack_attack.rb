class Rack::Attack
  ### Throttle /embed/* POSTs to 5/minute per IP ###
  throttle("embed/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.post? && req.path.start_with?("/embed/")
  end

  ### Custom response for throttled requests ###
  self.throttled_responder = lambda do |env|
    [429, { "Content-Type" => "text/plain" }, ["Too many requests. Please wait a minute and try again."]]
  end
end

# Enable in production + test (so we can write a test for it).
# In dev, leave off — local testing of the form shouldn't trigger it.
Rails.application.config.middleware.use Rack::Attack unless Rails.env.development?
