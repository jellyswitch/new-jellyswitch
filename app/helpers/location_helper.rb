module LocationHelper
  def location_select_options(locations)
    locations.map do |location|
      ["#{location.name} @ #{location.building_address}", location.id]
    end
  end
end
