
class OperatorsController < ApplicationController
  def index
    find_operators
    authorize @production_operators

    @production_reports = @production_operators.all.map do |operator|
      Jellyswitch::Report.new(operator)
    end

    @demo_reports = @demo_operators.all.map do |operator|
      Jellyswitch::Report.new(operator)
    end

    @production_staff = User.where(operator: @production_operators).admins.non_superadmins.count
    @demo_staff = User.where(operator: @demo_operators).admins.non_superadmins.count
  end

  def show
    find_operator
    authorize @operator
  end

  private

  def find_operators
    @operators = Operator.order("created_at DESC").all
    @production_operators = Operator.production.order("created_at ASC").all
    @demo_operators = Operator.demo.order("created_at ASC").all
  end

  def find_operator(key = :id)
    @operator = Operator.friendly.find(params[key])
  end
end
