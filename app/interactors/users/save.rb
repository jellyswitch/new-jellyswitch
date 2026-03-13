
class Users::Save
  include Interactor
  include FeedItemCreator
  include ErrorsHelper

  def call
    @user = User.new(context.params)
    context.user = @user

    if !context.operator.approval_required
      @user.approved = true
    end

    @user.operator = context.operator

    # Set terms_accepted_at when user accepts terms
    if @user.terms_accepted == "1" && @user.terms_accepted_at.blank?
      @user.terms_accepted_at = Time.current
    end

    # if user chose an original location and not having current location set, set current location to original location
    if @user.original_location_id.present? && @user.current_location_id.blank?
      @user.current_location_id = @user.original_location_id
    end

    # Admin-created users are auto-confirmed
    if context.admin_created
      @user.email_confirmed = true
    end

    if !@user.save
      context.fail!(message: "Unable to sign up. Please review errors. #{errors_for(@user)}")
    end

    context.notifiable = @user

    result = CreateStripeCustomer.call(user: @user, location: @user.original_location)

    if !result.success?
      context.fail!(message: result.message)
    end

    # Send confirmation email for self-signup users
    if !context.admin_created && !@user.email_confirmed?
      begin
        @user.generate_confirmation_token
        @user.send_confirmation_email
      rescue => e
        Rails.logger.error("Email confirmation send error: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
      end
    end

    # Schedule signup nudge email for self-signup users
    if !context.admin_created
      begin
        ScheduleSignupNudgeJob.perform_later(@user.id, context.operator.id)
      rescue => e
        Rails.logger.error("Signup nudge schedule error: #{e.class}: #{e.message}")
      end
    end
  end
end
