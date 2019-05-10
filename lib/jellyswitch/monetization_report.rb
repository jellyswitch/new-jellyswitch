class Jellyswitch::MonetizationReport
  attr_reader :location

  def initialize(location)
    @location = location
  end

  def office_income
    @office_income ||= location.offices.map do |office|
      income = office.office_leases.active.map(&:subscription).map(&:plan).flatten.sum {|p| p.amount_in_cents }.to_f / 100.0
      income_per_square_foot = income / office.square_footage

      office_income_klass.new(
        office,
        office.name,
        office.square_footage,
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
      nil,
      "Total Offices",
      square_footage,
      income,
      income_per_square_foot
    )
  end

  def room_income
    @room_income ||= location.rooms.map do |room|
      room_income_klass.new(
        room,
        room.name,
        0,
        0,
        0
      )
    end
  end

  def total_room_income
    @total_room_income  ||= room_income_klass.new(
      nil,
      "Total Rooms",
      0,
      0,
      0
    )
  end

  def flex_income
    @flex_income ||= location.operator.plans.map do |plan|
      income = plan.subscriptions.active.count * (plan.amount_in_cents.to_f / 100.0)

      flex_income_klass.new(
        plan,
        plan.name,
        0,
        income,
        0
      )

    end
  end

  def total_flex_income
    income = flex_income.sum {|f| f.income }
    income_per_square_foot = income.to_f / location.flex_square_footage

    @total_flex_income ||= flex_income_klass.new(
      nil,
      "Total Flex Income",
      location.flex_square_footage,
      income,
      income_per_square_foot
    )
  end

  private

  def office_income_klass
    Struct.new(:office, :name, :square_footage, :income, :income_per_square_foot)
  end

  def room_income_klass
    Struct.new(:room, :name, :square_footage, :income, :income_per_square_foot)
  end

  def flex_income_klass
    Struct.new(:plan, :name, :square_footage, :income, :income_per_square_foot)
  end
end