require "resolv"

# Rejects sign-ups whose email domain can't receive mail at all — no MX record
# and no A/AAAA fallback. Catches typo/fake domains ("user@gmial.con",
# "user@asdfasdf.invalid") that the disposable-domain list can't anticipate.
# Complements DisposableEmailValidator as front-door spam defense: stop the bad
# address before a User row exists, instead of leaning on the post-signup
# confirmation/approval gates.
#
# Two hard rules, because a DNS check touches the network:
#
#   1. NETWORK-GATED. Off unless ENV["VALIDATE_EMAIL_MX"] is truthy. This keeps
#      the whole test suite (which creates thousands of users) and local dev
#      from doing real DNS lookups on every create, and lets production enable
#      it as a deliberate, reversible flip (mirrors the Turnstile lenient-
#      rollout convention). Enable in prod with `VALIDATE_EMAIL_MX=true`.
#
#   2. FAIL-OPEN. Any DNS error/timeout is treated as "domain is fine" — a
#      flaky resolver or a slow authoritative server must NEVER block a real
#      person from signing up. We only reject when we positively resolve the
#      domain and find zero mail exchangers.
#
# Applied on :create only and skipped for admin-created members (see User).
class MxRecordValidator < ActiveModel::EachValidator
  # Per-query DNS timeout (seconds). Kept short so a slow resolver degrades to
  # fail-open quickly rather than holding the signup request open.
  LOOKUP_TIMEOUT_SECONDS = 2

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("VALIDATE_EMAIL_MX", false))
  end

  def validate_each(record, attribute, value)
    return if value.blank?
    return unless self.class.enabled?

    # An @-less value has no domain part — bail and let the format validation
    # reject it, instead of DNS-probing the whole string as a "domain".
    _local, at_sign, domain = value.to_s.downcase.strip.rpartition("@")
    return if at_sign.empty? || domain.blank?
    return if domain_can_receive_mail?(domain)

    record.errors.add(
      attribute,
      options[:message] || "doesn't look like a valid email address — its domain can't receive email.",
    )
  end

  private

  # True if the domain has at least one mail exchanger (MX), or — failing that —
  # an A/AAAA record (RFC 5321 §5.1 implicit MX). True on ANY lookup failure
  # (fail-open). Only a clean lookup that finds nothing returns false.
  def domain_can_receive_mail?(domain)
    Resolv::DNS.open do |dns|
      dns.timeouts = LOOKUP_TIMEOUT_SECONDS
      return true if dns.getresources(domain, Resolv::DNS::Resource::IN::MX).any?
      return true if dns.getresources(domain, Resolv::DNS::Resource::IN::A).any?
      return true if dns.getresources(domain, Resolv::DNS::Resource::IN::AAAA).any?
      false
    end
  rescue => e
    Rails.logger.warn("[MxRecordValidator] fail-open for #{domain}: #{e.class}: #{e.message}")
    true
  end
end
