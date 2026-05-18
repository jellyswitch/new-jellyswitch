module Turnstile
  class Verifier
    Result = Struct.new(:success?, :error_codes, keyword_init: true)

    VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify".freeze

    def self.call(token:, remote_ip:)
      new(token, remote_ip).call
    end

    def initialize(token, remote_ip)
      @token = token
      @remote_ip = remote_ip
    end

    def call
      return Result.new(success?: true, error_codes: []) if ENV["TURNSTILE_SECRET"].blank?

      response = Faraday.post(VERIFY_URL, {
        secret: ENV["TURNSTILE_SECRET"],
        response: @token,
        remoteip: @remote_ip,
      })

      body = JSON.parse(response.body)
      Result.new(success?: body["success"] == true, error_codes: Array(body["error-codes"]))
    rescue Faraday::Error, JSON::ParserError => e
      Honeybadger.notify(e, context: { remote_ip: @remote_ip })
      Result.new(success?: false, error_codes: ["network-error"])
    end
  end
end
