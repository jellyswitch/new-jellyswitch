class Jellyswitch::MonetizationReport
  attr_reader :location

  def initialize(location)
    @location = location
  end

  def office_income
    @office_income ||= location.offices.map do |office|
      income = office.office_leases.active.map(&:subscription).map(&:plan).flatten.sum {|p| p.amount_in_cents }.to_f
      income_per_square_foot = income / 1500

      office_income_klass.new(
        office.name,
        1500,
        income,
        income_per_square_foot
      )
    end
  end

  def total_office_income
    square_footage = office_income.sum { |o| o.square_footage }
    income = office_income.sum{ |o| o.income }
    income_per_square_foot = income / square_footage

    @total_office_income ||= office_income_klass.new(
      "Total Offices",
      square_footage,
      income,
      income_per_square_foot
    )
  end

  private

  def office_income_klass
    Struct.new(:name, :square_footage, :income, :income_per_square_foot)
  end
end