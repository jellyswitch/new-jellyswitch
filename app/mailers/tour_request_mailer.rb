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

  # Visitor-facing acknowledgment — the staff alert above goes to admins, but
  # the requester previously got only the widget's thank-you screen and then
  # silence until someone called. Branded sender; replies go to the operator.
  def confirmation
    @activity  = params[:activity]
    @requester = @activity.user
    @user      = @requester
    @location  = @activity.subject_type == "Location" ? @activity.subject : nil
    @operator  = @activity.operator
    @preferred_time = @activity.payload["preferred_time"]

    mail(
      to: @requester.email,
      from: @operator.sender_from_address,
      reply_to: @operator.sender_email.presence,
      subject: "Your tour request at #{@operator.name}",
    )
  end
end
