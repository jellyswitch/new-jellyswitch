class OperatorsController < ApplicationController
  def index
    find_operators
    authorize @operators
  end

  def show
    find_operator
    authorize @operator
  end

  private

  def find_operators
    @operators = Operator.all
  end

  def find_operator(key=:id)
    @operator = Operator.find(params[key])
  end
end