Geocoder.configure(
  lookup: :nominatim,
  http_headers: { "User-Agent" => "Jellyswitch/1.0 (admin@jellyswitch.com)" },
  timeout: 5,
  units: :mi,
)
