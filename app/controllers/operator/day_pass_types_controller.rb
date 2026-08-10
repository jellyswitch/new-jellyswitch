
class Operator::DayPassTypesController < Operator::BaseController
  include DayPassTypesHelper
  before_action :find_day_pass_type, only: [:show, :edit, :update, :destroy]
  before_action :background_image

  def index
    find_day_pass_types
    authorize @day_pass_types
  end

  def show
    authorize @day_pass_type
  end

  def new
    @day_pass_type = DayPassType.new
    authorize @day_pass_type
  end

  def edit
    authorize @day_pass_type
  end

  def create
    authorize DayPassType.new
    result = CreateDayPassType.call(params: day_pass_type_params)

    @day_pass_type = result.day_pass_type
    if result.success?
      sync_office_room_pool!
      if params[:add_day_pass_type_and_add_another].present?
        turbo_redirect(new_day_pass_type_path, action: "replace")
      else
        turbo_redirect(day_pass_type_path(@day_pass_type))
      end
    else
      flash[:error] = result.message
      render :new, status: 422
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def update
    authorize @day_pass_type

    if @day_pass_type.update(day_pass_type_update_params)
      sync_office_room_pool!
      flash[:success] = "Day pass type was successfully updated."
      turbo_redirect(day_pass_type_path(@day_pass_type))
    else
      render :edit, status: 422
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def destroy
    authorize @day_pass_type
    @day_pass_type.update(available: false)
    flash[:success] = "Day pass type was successfully archived."
    turbo_redirect(day_pass_types_url)
  end

  def archived
    @day_pass_types = current_location.day_pass_types.unavailable
    authorize @day_pass_types
  end

  def unarchive
    find_day_pass_type(:day_pass_type_id)
    authorize @day_pass_type
    @day_pass_type.update(available: true)
    if @day_pass_type.save
      flash[:success] = "Day pass type unarchived."
    else
      flash[:error] = "Could not unarchive day pass type."
    end
    turbo_redirect(day_pass_types_path)
  end

  def visible
    setting(:visible)
  end

  def always_allow_building_access
    setting(:always_allow_building_access)
  end

  def available
    setting(:available)
  end

  private

  def find_day_pass_type(key = :id)
    @day_pass_type = current_location.day_pass_types.find(params[key])
  end

  def find_day_pass_types
    @day_pass_types = current_location.day_pass_types.available
  end

  def setting(symbol)
    find_day_pass_type(:day_pass_type_id)
    result = ToggleValue.call(object: @day_pass_type, value: symbol)

    if !result.success?
      flash[:error] = result.message
    end

    turbo_redirect(day_pass_type_path(@day_pass_type), action: "replace")
  end

  # Syncs the Day Office room pool after a successful create/update (Task
  # 13, ADR 0026) — full-list semantics, see DayPassType#assign_office_rooms!.
  # A type saved as day_office gets whatever the form posted (an unsubmitted
  # or empty office_room_positions clears the pool, matching the form's
  # "blank = not in the pool" copy). A type saved as standard never carries
  # a pool, so a type switched FROM day_office back to standard has its pool
  # cleared here too — otherwise the orphaned rows would silently reappear
  # if the type is ever switched back to day_office later.
  #
  # The type record itself is already saved by the time this runs — a pool
  # row failing validation (e.g. a stray cross-location room id) must not
  # look like the whole save failed. Report it as its own flash and let the
  # action's normal redirect proceed instead of raising into the generic
  # rescue => e handler (which would send a misleading "an error occurred"
  # and mask that the type itself is fine).
  def sync_office_room_pool!
    if @day_pass_type.day_office?
      @day_pass_type.assign_office_rooms!(office_room_positions_params)
    elsif @day_pass_type.day_pass_type_rooms.exists?
      @day_pass_type.assign_office_rooms!({})
    end
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = "#{@day_pass_type.name} was saved, but the room pool couldn't be updated: " \
                     "#{e.record.errors.full_messages.to_sentence}"
  end
end
