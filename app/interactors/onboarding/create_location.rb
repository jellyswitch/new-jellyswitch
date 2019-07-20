class Onboarding::CreateLocation
  include Interactor
  include ErrorsHelper

  delegate :operator, :name, :description, :square_footage, :street_address, :city, :state, :zip, :time_zone, to: :context

  def call
    loc = operator.locations.new(
      name: name,
      snippet: description,
      square_footage: square_footage,
      building_address: street_address,
      city: city,
      state: state,
      zip: zip,
      time_zone: time_zone
    )

    if loc.save
      context.location = loc
    else
      context.fail!(message: errors_for(loc))
    end
  end

  def rollback
    context.location.destroy!
  end
end