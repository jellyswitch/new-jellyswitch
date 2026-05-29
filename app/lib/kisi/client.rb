require "net/http/persistent"

module Kisi
  # Thin wrapper around api.kisi.io that maintains a process-wide persistent
  # HTTPS connection. `Net::HTTP::Persistent` is internally thread-safe (it
  # holds a connection per (host, thread) pair), so a single shared instance
  # is safe across all Sidekiq worker threads.
  #
  # Why: every unlock previously opened a fresh socket + paid the TLS
  # handshake — ~300-500ms each, which is most of the perceived latency
  # between Face ID and the door physically clicking. Reusing the socket
  # collapses subsequent unlocks to ~1 round-trip.
  class Client
    def self.connection
      @connection ||= Net::HTTP::Persistent.new(name: "kisi").tap do |c|
        # Keep an idle socket alive for a minute — comfortably covers normal
        # door traffic without holding state forever if the worker goes quiet.
        c.idle_timeout = 60
      end
    end

    # Performs the unlock against api.kisi.io for the given Door, returning a
    # uniform { success, code, parsed, body } hash so callers don't have to
    # know about Net::HTTPResponse.
    def self.unlock(door)
      uri = URI.parse("https://api.kisi.io/locks/#{door.kisi_id}/unlock")
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "KISI-LOGIN #{door.location.kisi_api_key}"
      request["Content-Type"]  = "application/json"
      request["Accept"]        = "application/json"

      response = connection.request(uri, request)

      parsed = begin
        JSON.parse(response.body) if response.body && !response.body.empty?
      rescue JSON::ParserError
        response.body
      end

      {
        success: response.is_a?(Net::HTTPSuccess),
        code:    response.code.to_i,
        parsed:  parsed,
        body:    response.body,
      }
    end
  end
end
