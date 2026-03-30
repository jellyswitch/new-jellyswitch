class CpiFetchJob < ApplicationJob
  queue_as :default

  def perform
    # Fetch all CPI indices that are actively used by leases
    series_ids = OfficeLease.where(escalation_type: "cpi_index")
                            .where.not(cpi_index_series_id: nil)
                            .distinct
                            .pluck(:cpi_index_series_id)

    # Always fetch the default CPI-U
    series_ids << "CUSR0000SA0"
    series_ids.uniq!

    series_ids.each do |series_id|
      CpiCalculator.fetch_and_cache(series_id)
      Rails.logger.info("CpiFetchJob: Cached CPI rate for #{series_id}")
    rescue => e
      Honeybadger.notify(e)
      Rails.logger.error("CpiFetchJob: Failed to fetch #{series_id}: #{e.message}")
    end
  end
end
