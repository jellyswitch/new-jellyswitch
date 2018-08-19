class DayPassesController < ApplicationController
  def new
    @day_pass = DayPass.new
    authorize @day_pass
    background_image
  end

  def create
    @day_pass = new_day_pass
    authorize @day_pass

    if @day_pass.save
      flash[:notice] = "Success! Welcome to #{Rails.application.config.x.customization.name}."
      redirect_to root_path
    else
      flash[:error] = "An error occurred."
      render :new
    end
  end

  private

  def day_pass_params
    params.require(:day_pass).permit(:day)
  end

  def new_day_pass
    day_pass = DayPass.new(day_pass_params)
    day_pass.user = current_user
    day_pass
  end
end