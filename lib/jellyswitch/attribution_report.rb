# frozen_string_literal: true

module Jellyswitch
  # Data › Conversions. Answers, for one location and period:
  #   * the funnel: visits → leads / signups → first purchases → revenue
  #   * each of those by first-touch channel and by campaign
  #   * self-serve share: what closed with no staff in the loop, and after hours
  #
  # Reads Conversion rows (written live by every purchase/signup path and
  # reconstructed for history by `rails attribution:backfill`) plus Ahoy visits
  # for the top of the funnel. Visits are operator-wide (one web host per
  # brand), so the visit counts are brand-level while everything below the
  # visit row is location-scoped.
  class AttributionReport
    CHANNEL_LABELS = {
      "paid_search"    => "Google Ads / paid search",
      "paid_social"    => "Paid social",
      "organic_search" => "Organic search",
      "social"         => "Social",
      "email"          => "Email campaign",
      "referral"       => "Referral site",
      "website"        => "Your website (widget)",
      "direct"         => "Direct / typed in",
      "app"            => "Mobile app",
      "other_campaign" => "Other tagged campaign",
      "unknown"        => "Unknown (no visit on record)",
    }.freeze
    # Referral rows are split per referring domain so the operator's own
    # marketing site shows as its own line instead of hiding real referrals.
    REFERRAL_PREFIX = "referral:"

    CHANNEL_ORDER = CHANNEL_LABELS.keys.freeze
    MAX_VISIT_DAYS = 365

    attr_reader :location, :operator, :period_days, :range

    def initialize(location, period_days: 90, host: nil)
      @location = location
      @operator = location.operator
      @period_days = period_days
      @range = period_days.days.ago.beginning_of_day..Time.current
      @host = host
    end

    def self.channel_label(channel)
      key = channel.to_s
      return "Referral · #{key.delete_prefix(REFERRAL_PREFIX)}" if key.start_with?(REFERRAL_PREFIX)
      CHANNEL_LABELS[key] || key.humanize.presence || "Unknown"
    end

    # Group key for a conversion/user/visit: referral rows carry their domain.
    def self.channel_key(channel, referrer_domain)
      return "unknown" if channel.blank?
      channel == "referral" && referrer_domain.present? ? "#{REFERRAL_PREFIX}#{referrer_domain}" : channel
    end

    # ── Funnel ────────────────────────────────────────────────────────────
    def funnel
      @funnel ||= {
        visits: visits.count,
        visitors: visits.distinct.count(:visitor_token),
        leads: conversions.leads.where(kind: %w[tour_request chat_lead]).count,
        signups: conversions.where(kind: "signup").count,
        first_purchases: first_purchase_user_ids.size,
        purchases: conversions.revenue.count,
        revenue: conversions.revenue.sum(:amount_cents) / 100.0,
      }
    end

    # ── By channel ───────────────────────────────────────────────────────
    # { channel => { visits:, leads:, signups:, purchases:, revenue: } }
    def by_channel
      @by_channel ||= begin
        rows = Hash.new { |h, k| h[k] = { visits: 0, leads: 0, signups: 0, purchases: 0, revenue: 0.0 } }

        visit_channels.each { |ch, n| rows[ch][:visits] += n }

        conversions.group(:channel, :referrer_domain, :kind).count.each do |(channel, domain, kind), n|
          ch = self.class.channel_key(channel, domain)
          case kind
          when "signup" then rows[ch][:signups] += n
          when "tour_request", "chat_lead" then rows[ch][:leads] += n
          else rows[ch][:purchases] += n if Conversion::REVENUE_KINDS.include?(kind)
          end
        end
        # $0 rows are activity, not purchases — take them back out.
        conversions.revenue_kinds.where(amount_cents: 0).group(:channel, :referrer_domain).count.each do |(channel, domain), n|
          rows[self.class.channel_key(channel, domain)][:purchases] -= n
        end
        conversions.revenue.group(:channel, :referrer_domain).sum(:amount_cents).each do |(channel, domain), cents|
          rows[self.class.channel_key(channel, domain)][:revenue] += cents / 100.0
        end

        rows.sort_by { |ch, r| [-r[:revenue], -r[:signups], -r[:visits], CHANNEL_ORDER.index(ch.sub(/:.*/, "")) || 99] }.to_h
      end
    end

    # ── By campaign (UTM) ────────────────────────────────────────────────
    def by_campaign
      @by_campaign ||= begin
        rows = Hash.new { |h, k| h[k] = { visits: 0, leads: 0, signups: 0, purchases: 0, revenue: 0.0, source: nil } }

        visits.where.not(utm_campaign: [nil, ""]).group(:utm_campaign, :utm_source).count.each do |(camp, src), n|
          rows[camp][:visits] += n
          rows[camp][:source] ||= src
        end
        conversions.where.not(campaign: [nil, ""]).group(:campaign, :source, :kind).count.each do |(camp, src, kind), n|
          rows[camp][:source] ||= src
          case kind
          when "signup" then rows[camp][:signups] += n
          when "tour_request", "chat_lead" then rows[camp][:leads] += n
          else rows[camp][:purchases] += n
          end
        end
        conversions.revenue.where.not(campaign: [nil, ""]).group(:campaign).sum(:amount_cents).each do |camp, cents|
          rows[camp][:revenue] += cents / 100.0
        end

        rows.sort_by { |_, r| [-r[:revenue], -r[:signups], -r[:visits]] }.to_h
      end
    end

    # ── Self-serve share ─────────────────────────────────────────────────
    # Only live-tracked rows know who acted; backfilled history is excluded
    # so the share is honest rather than padded.
    def self_serve
      @self_serve ||= begin
        live = conversions.revenue.where.not(surface: "backfill")
        by_kind = Hash.new { |h, k| h[k] = { self_serve: 0, staff: 0, self_serve_revenue: 0.0, staff_revenue: 0.0 } }
        live.group(:kind, :self_serve).count.each do |(kind, ss), n|
          by_kind[kind][ss ? :self_serve : :staff] += n
        end
        live.group(:kind, :self_serve).sum(:amount_cents).each do |(kind, ss), cents|
          by_kind[kind][ss ? :self_serve_revenue : :staff_revenue] += cents / 100.0
        end

        total_rev = by_kind.values.sum { |r| r[:self_serve_revenue] + r[:staff_revenue] }
        ss_rev = by_kind.values.sum { |r| r[:self_serve_revenue] }
        total_n = by_kind.values.sum { |r| r[:self_serve] + r[:staff] }
        ss_n = by_kind.values.sum { |r| r[:self_serve] }

        after_hours = live.where(self_serve: true).pluck(:occurred_at).count { |t| !location.open_at?(t) }

        {
          by_kind: by_kind.sort_by { |_, r| -(r[:self_serve_revenue] + r[:staff_revenue]) }.to_h,
          tracked_purchases: total_n,
          self_serve_purchases: ss_n,
          self_serve_share: total_n.zero? ? nil : (100.0 * ss_n / total_n).round,
          tracked_revenue: total_rev,
          self_serve_revenue: ss_rev,
          self_serve_revenue_share: total_rev.zero? ? nil : (100.0 * ss_rev / total_rev).round,
          after_hours_purchases: after_hours,
          tracking_since: Conversion.where(operator: operator).where.not(surface: "backfill").minimum(:occurred_at),
        }
      end
    end

    # Most recent conversions for the activity list.
    def recent(limit = 25)
      conversions.includes(:user).order(occurred_at: :desc).limit(limit)
    end

    # People acquired through a channel (for the drill-down). A split referral
    # key ("referral:coworktahoe.com") narrows to that referring domain.
    def people_for_channel(channel)
      scope = User.where(operator: operator, original_location_id: location.id)
      if channel.to_s.start_with?(REFERRAL_PREFIX)
        scope = scope.where(acquisition_channel: "referral", acquisition_referrer: channel.to_s.delete_prefix(REFERRAL_PREFIX))
      else
        scope = scope.where(acquisition_channel: channel)
      end
      scope.order(acquired_at: :desc).limit(200)
    end

    # Visits are capped at a year even for "All Time" (see MAX_VISIT_DAYS).
    def visits_capped?
      period_days > MAX_VISIT_DAYS
    end

    def conversions
      @conversions ||= Conversion.for_location(location).between(range)
    end

    private

    def first_purchase_user_ids
      @first_purchase_user_ids ||= begin
        firsts = Conversion.where(operator: operator).revenue.where.not(user_id: nil)
                           .group(:user_id).minimum(:occurred_at)
        firsts.select { |_, at| range.cover?(at) }.keys
      end
    end

    # Brand-level: every visit that landed on this operator's host, minus
    # staff (admins/managers using the admin) — they aren't prospects.
    def visits
      @visits ||= begin
        days = [period_days, MAX_VISIT_DAYS].min
        scope = Ahoy::Visit.where(started_at: days.days.ago.beginning_of_day..Time.current)
        staff_ids = User.where(operator: operator).where("admin = true OR role IN (?)", %w[admin superadmin general_manager community_manager]).select(:id)
        scope = scope.where("ahoy_visits.user_id IS NULL OR ahoy_visits.user_id NOT IN (?)", staff_ids)
        if @host.present?
          scope.where("landing_page LIKE ?", "%://#{@host}/%")
        else
          scope.where("landing_page LIKE ?", "%://#{operator.subdomain}.%")
        end
      end
    end

    def visit_channels
      @visit_channels ||= begin
        counts = Hash.new(0)
        visits.pluck(:referrer, :referring_domain, :landing_page, :utm_source, :utm_medium, :utm_campaign, :user_agent)
              .each do |ref, dom, land, src, med, camp, ua|
          surface = ua.to_s.include?("Jellyswitch") ? "app" : "web"
          c = Attribution::Classifier.call(referrer: ref, referring_domain: dom, landing_page: land,
                                           utm_source: src, utm_medium: med, utm_campaign: camp,
                                           surface: surface)
          counts[self.class.channel_key(c.channel, c.referrer_domain)] += 1
        end
        counts
      end
    end
  end
end
