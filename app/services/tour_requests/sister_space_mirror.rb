module TourRequests
  # Untethered-only customization (ADR 0030): a tour request that comes in
  # through Untethered's tour widget for their Lake Tahoe, NV (Zephyr Cove)
  # location is also logged as a tour request at Cowork Tahoe — the sister
  # space across the lake, a separate operator/tenant. A Tahoe prospect is a
  # prospect for both spaces, and the Zephyr Cove staff handle both, so the
  # mirror is a CRM record (Person + tour_request Activity under Cowork
  # Tahoe) rather than a second round of alerts: the Untethered staff alert
  # simply notes the mirror and links to it. Cowork Tahoe's own admins are
  # NOT paged and the visitor gets one confirmation, not two.
  #
  # Keyed by subdomain + city rather than ids so the rule reads as prose and
  # works in every environment; Fulton, MO requests never mirror.
  class SisterSpaceMirror
    RULES = {
      "untethered" => { source_city: "Zephyr Cove", target_subdomain: "tml" },
    }.freeze

    def self.call(activity)
      new(activity).call
    end

    def initialize(activity)
      @activity = activity
    end

    # Returns the mirrored Activity, or nil when the rule doesn't apply (or
    # anything goes wrong — the primary request must never fail because of
    # the mirror).
    def call
      rule = RULES[@activity.operator&.subdomain]
      return nil unless rule
      return nil unless @activity.kind.to_s == "tour_request"

      source_location = @activity.subject_type == "Location" ? @activity.subject : nil
      return nil unless source_location && source_location.city.to_s.strip.casecmp?(rule[:source_city])

      target = Operator.find_by(subdomain: rule[:target_subdomain])
      return nil if target.nil? || target.id == @activity.operator_id

      mirror = ActsAsTenant.with_tenant(target) { log_mirror(target, source_location) }

      @activity.update!(payload: @activity.payload.merge(
        "mirrored_to" => {
          "operator_subdomain" => target.subdomain,
          "operator_name"      => target.name,
          "location_name"      => mirror.subject&.name,
          "user_id"            => mirror.user_id,
          "activity_id"        => mirror.id,
        },
      ))
      mirror
    rescue => e
      Rails.logger.error("[TourRequests::SisterSpaceMirror] activity #{@activity.id}: #{e.class}: #{e.message}")
      nil
    end

    private

    def log_mirror(target, source_location)
      requester = @activity.user
      target_location = target.locations.where(visible: true).order(:id).first

      user = User.find_or_initialize_by(email: requester.email, operator: target)
      if user.new_record?
        user.name = requester.name
        user.phone = requester.phone if requester.phone.present?
        user.original_location_id = target_location&.id
        user.admin_created = true
        user.password = SecureRandom.hex(16)
      end
      user.save!

      Activity.log(
        user: user,
        operator: target,
        kind: :tour_request,
        occurred_at: @activity.occurred_at,
        subject: target_location,
        payload: @activity.payload.slice("message", "preferred_time", "source", "referrer").merge(
          "mirrored_from" => {
            "operator_subdomain" => @activity.operator.subdomain,
            "operator_name"      => @activity.operator.name,
            "location_name"      => source_location.name,
            "user_id"            => requester.id,
            "activity_id"        => @activity.id,
          },
        ),
      )
    end
  end
end
