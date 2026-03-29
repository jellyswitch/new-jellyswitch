class Api::DoorsController < ApplicationController
  include DoorsHelper
  protect_from_forgery with: :null_session
  before_action :authenticate_api_user

  def index
    if current_location.nil?
      render json: { error: "No location set" }, status: 400
      return
    end

    doors = current_location.doors.available
    render json: doors.map { |d| { id: d.id, name: d.name, private: d.private } }
  rescue => e
    Rails.logger.error("[DoorsAPI] Error in index: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: 500
  end

  def unlock
    @door = Door.find(params[:id])
    authorize @door, :open?

    # Log the door punch
    DoorPunch.create!(user: current_user, door: @door, operator: current_tenant)

    # Call Kisi API to physically unlock the door
    begin
      kisi_url = url(@door)
      kisi_result = HTTParty.post(kisi_url, headers: headers(@door))
      DoorPunch.create(user: current_user, door: @door, operator: current_tenant, json: kisi_result.parsed_response)
      Rails.logger.info("[DoorOpen:API] #{@door.name} kisi_id=#{@door.kisi_id} => #{kisi_result.code}")

      if kisi_result.success?
        render json: { success: true, door: @door.name, message: "#{@door.name} unlocked" }
      else
        Rails.logger.error("[DoorOpen:API] Kisi error: #{kisi_result.code} #{kisi_result.body}")
        render json: { success: false, door: @door.name, message: "Failed to unlock #{@door.name}" }, status: 502
      end
    rescue => e
      Rails.logger.error("[DoorOpen:API] Error unlocking #{@door.name}: #{e.class}: #{e.message}")
      render json: { success: false, message: "Error: #{e.message}" }, status: 500
    end
  end

  private

  def authenticate_api_user
    unless current_user
      render json: { error: "Unauthorized" }, status: 401
    end
  end
end
