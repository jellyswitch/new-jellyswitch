class CpiCalculator
  BLS_API_URL = "https://api.bls.gov/publicAPI/v2/timeseries/data/".freeze

  CPI_INDICES = {
    "CUSR0000SA0" => "CPI-U All Items",
    "CUSR0000SA0L1E" => "CPI-U Less Food & Energy",
    "CWSR0000SA0" => "CPI-W All Items",
    "CUSR0000SAH1" => "CPI-U Shelter",
    "CUUR0400SA0" => "CPI-U West Region"
  }.freeze

  def self.annual_rate(series_id = "CUSR0000SA0")
    cached = Rails.cache.read("bls_cpi:#{series_id}")
    return cached if cached.present?

    # If no cache, try to fetch
    fetch_and_cache(series_id)
    Rails.cache.read("bls_cpi:#{series_id}") || 3.0 # fallback to 3% if fetch fails
  end

  def self.fetch_and_cache(series_id)
    current_year = Time.current.year
    response = HTTParty.post(
      BLS_API_URL,
      body: {
        seriesid: [series_id],
        startyear: (current_year - 1).to_s,
        endyear: current_year.to_s,
        registrationkey: ENV["BLS_API_KEY"]
      }.to_json,
      headers: { "Content-Type" => "application/json" },
      timeout: 10
    )

    return unless response.success?

    data = response.parsed_response
    return unless data["status"] == "REQUEST_SUCCEEDED"

    series_data = data.dig("Results", "series", 0, "data")
    return unless series_data.present?

    # Find most recent month's value and same month last year
    sorted = series_data.sort_by { |d| [d["year"].to_i, d["period"].delete("M").to_i] }.reverse
    current = sorted.first
    same_month_last_year = sorted.find do |d|
      d["year"].to_i == current["year"].to_i - 1 && d["period"] == current["period"]
    end

    if current && same_month_last_year
      current_val = current["value"].to_f
      previous_val = same_month_last_year["value"].to_f
      rate = ((current_val - previous_val) / previous_val * 100).round(1)
      Rails.cache.write("bls_cpi:#{series_id}", rate, expires_in: 35.days)
      rate
    end
  rescue StandardError => e
    Honeybadger.notify(e)
    Rails.logger.error("CpiCalculator fetch failed: #{e.class}: #{e.message}")
    nil
  end

  def self.options_for_select
    CPI_INDICES.map { |id, name| [name, id] }
  end
end
