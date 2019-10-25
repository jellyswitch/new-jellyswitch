class Operator::RsvpsController < Operator::BaseController
  before_action :background_image
  before_action :find_event

  def going
    result = Events::Going.call(
      event: @event,
      user: current_user
    )

    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(event_path(@event), action: "replace")
  end

  def not_going
    result = Events::NotGoing.call(
      event: @event,
      user: current_user
    )

    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(event_path(@event), action: "replace")
  end

  private

  def find_event
    @event = current_tenant.events.find(params[:event_id])
  end
end