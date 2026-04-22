# Dev/staging-only time travel. When SIMULATED_TIME is set in the
# environment (e.g. "2026-04-22T06:00:00-07:00"), every call to
# Time.current / Time.now / Date.current / DateTime.now returns a time
# computed as (simulated_origin + real_elapsed_since_boot). This lets
# us exercise "morning of a booking" flows without fudging the DB.
#
# Unset the env var (or leave it blank) to return to real time.

if ENV["SIMULATED_TIME"].present?
  begin
    origin = Time.zone.parse(ENV["SIMULATED_TIME"])
    raise "could not parse" unless origin

    boot_time = Time.now.utc
    $__simulated_origin = origin
    $__simulated_boot = boot_time

    Rails.logger.info("[SimulatedTime] Pinning Time.current to #{origin} (offset from real)")

    Time.singleton_class.prepend(Module.new do
      def current
        return super unless $__simulated_origin
        $__simulated_origin + (Time.now.utc - $__simulated_boot)
      end

      def now
        return super unless $__simulated_origin
        ($__simulated_origin + (Time.now.utc - $__simulated_boot)).in_time_zone.time
      end
    end)

    ActiveSupport::TimeZone.class_eval do
      alias_method :__real_now, :now unless method_defined?(:__real_now)

      def now
        return __real_now unless $__simulated_origin
        ($__simulated_origin + (Time.now.utc - $__simulated_boot)).in_time_zone(self)
      end
    end

    Date.singleton_class.prepend(Module.new do
      def current
        return super unless $__simulated_origin
        Time.current.to_date
      end

      def today
        return super unless $__simulated_origin
        Time.current.to_date
      end
    end)
  rescue => e
    Rails.logger.error("[SimulatedTime] Failed to init: #{e.class}: #{e.message}")
  end
end
