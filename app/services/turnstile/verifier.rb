module Turnstile
  class Verifier
    Result = Struct.new(:success?, :error_codes, keyword_init: true)

    VERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify".freeze

    # `context` labels the call site (e.g. "operator_signup", "tour_request")
    # so the structured logs can be sliced per protected form.
    def self.call(token:, remote_ip:, context: nil)
      new(token, remote_ip, context).call
    end

    def initialize(token, remote_ip, context = nil)
      @token = token
      @remote_ip = remote_ip
      @context = context
    end

    def call
      return Result.new(success?: true, error_codes: []) if ENV["TURNSTILE_SECRET"].blank?

      response = Faraday.post(VERIFY_URL, {
        secret: ENV["TURNSTILE_SECRET"],
        response: @token,
        remoteip: @remote_ip,
      })

      body = JSON.parse(response.body)
      log_outcome(Result.new(success?: body["success"] == true, error_codes: Array(body["error-codes"])))
    rescue Faraday::Error, JSON::ParserError => e
      Honeybadger.notify(e, context: { remote_ip: @remote_ip, turnstile_context: @context })
      log_outcome(Result.new(success?: false, error_codes: ["network-error"]))
    end

    private

    # Emits one structured line per verification so pass/fail rates and the
    # *distribution* of error codes are queryable from the Rails log. The error
    # code is what tells a misconfiguration (`invalid-input-secret` — we block
    # everyone) apart from bots bouncing off (`missing-input-response`) or real
    # users hitting friction (`timeout-or-duplicate`). Returns the result so
    # callers can `log_outcome(...)` as the method's tail expression.
    def log_outcome(result)
      Rails.logger.info({
        event:       "turnstile_verification",
        context:     @context,
        outcome:     result.success? ? "pass" : "fail",
        error_codes: result.error_codes,
        remote_ip:   @remote_ip,
      }.to_json)
      result
    end
  end
end
