class TourRequestMailer < ApplicationMailer
  def new_request
    @recipient = params[:recipient]
    @activity  = params[:activity]
    @requester = @activity.user
    @location  = @activity.subject_type == "Location" ? @activity.subject : nil
    @operator  = @activity.operator
    @message   = @activity.payload["message"]
    @preferred_time = @activity.payload["preferred_time"]

    mail(
      to: @recipient.email,
      subject: "New tour request: #{@requester.name}",
    )
  end
end
