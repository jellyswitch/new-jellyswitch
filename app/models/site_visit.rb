# == Schema Information
#
# Table name: site_visits
#
#  id               :bigint(8)        not null, primary key
#  channel          :string
#  host             :string
#  landing_page     :string
#  last_seen_at     :datetime         not null
#  page_views       :integer          default(1), not null
#  referrer         :string
#  referring_domain :string
#  source           :string
#  started_at       :datetime         not null
#  user_agent       :string
#  utm_campaign     :string
#  utm_content      :string
#  utm_medium       :string
#  utm_source       :string
#  utm_term         :string
#  visitor_id       :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  operator_id      :bigint(8)        not null
#
# A session on the operator's own marketing site (coworktahoe.com,
# untethered.space), reported by the concierge launcher beacon. This is the
# "one step before" the operator's site that Jellyswitch's own Ahoy visits
# can't see. Sessionized like GA: a page view within 4h of the visitor's last
# one extends the session; otherwise it starts a new one classified from its
# own referrer / UTM tags.

class SiteVisit < ApplicationRecord
  belongs_to :operator

  SESSION_WINDOW = 4.hours
  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_term utm_content].freeze

  validates :visitor_id, :started_at, :last_seen_at, presence: true

  scope :between, ->(range) { where(started_at: range) }

  # Upsert a page view into the visitor's current session. Returns the session
  # row, or nil when the payload is unusable. Never raises to the caller.
  def self.record(operator:, visitor_id:, url:, referrer: nil, user_agent: nil)
    vid = visitor_id.to_s.strip[0, 64]
    return nil if operator.nil? || vid.blank? || url.blank?
    uri = URI.parse(url.to_s) rescue nil
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

    now = Time.current
    current = where(operator: operator, visitor_id: vid).where("last_seen_at > ?", now - SESSION_WINDOW)
                .order(last_seen_at: :desc).first
    if current
      current.update_columns(page_views: current.page_views + 1, last_seen_at: now)
      return current
    end

    ref = referrer.to_s.presence
    ref_host = (URI.parse(ref).host rescue nil).to_s.downcase.delete_prefix("www.")
    ref = nil if ref && ref_host == uri.host.downcase.delete_prefix("www.") # internal navigation
    utm = Rack::Utils.parse_query(uri.query.to_s).slice(*UTM_KEYS).transform_values { |v| Array(v).first.to_s[0, 255] }
    result = Attribution::Classifier.call(
      referrer: ref, landing_page: url.to_s,
      utm_source: utm["utm_source"], utm_medium: utm["utm_medium"], utm_campaign: utm["utm_campaign"],
      surface: "web",
    )

    create!(
      operator: operator, visitor_id: vid, host: uri.host[0, 255], landing_page: url.to_s[0, 255],
      referrer: ref&.first(255), referring_domain: result.referrer_domain&.first(255),
      channel: result.channel, source: result.source&.first(255),
      started_at: now, last_seen_at: now, page_views: 1, user_agent: user_agent.to_s.presence&.first(255),
      **utm,
    )
  rescue => e
    Rails.logger.warn("SiteVisit.record skipped: #{e.class}: #{e.message}")
    nil
  end
end
