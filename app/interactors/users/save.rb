
class Users::Save
  include Interactor
  include FeedItemCreator
  include ErrorsHelper

  def call
    # A Person the widgets (tour request, concierge, office inventory) or the
    # sister-space mirror created is a CRM stub: random password, unconfirmed
    # email, no terms, nothing bought. When that person later signs up with
    # the same email, complete THAT record instead of failing with "Email has
    # already been taken" — their tour history and point of contact survive
    # and, from their side, it's an ordinary signup. Anything with substance
    # (confirmed, approved, accepted terms, staff, purchases) is never claimed.
    stub = claimable_stub
    @user = stub || User.new
    @user.assign_attributes(context.params)
    context.user = @user
    context.claimed = stub.present?

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

    # Admin-created users are auto-confirmed and skip phone/TOS validations
    if context.admin_created
      @user.email_confirmed = true
      @user.admin_created = true
    end

    # Claiming is an UPDATE, so the create-only rules (password, phone, terms,
    # email format) must be asked for explicitly or a claim could skip them.
    if context.claimed && !@user.valid?(:create)
      context.fail!(message: "Unable to sign up. Please review errors. #{errors_for(@user)}")
    end

    # A claim runs save + Stripe in one transaction so a Stripe failure rolls
    # the stub back to exactly what it was (still claimable on retry) instead
    # of leaving it half-completed with terms stamped and un-claimable. Fresh
    # signups keep their existing non-transactional behavior — an admin-created
    # member must SURVIVE a Stripe failure (see below), which a rollback would
    # undo.
    if context.claimed
      User.transaction { persist_and_bill! }
    else
      persist_and_bill!
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

  private

  def persist_and_bill!
    @user = context.user

    begin
      if !@user.save
        context.fail!(message: "Unable to sign up. Please review errors. #{errors_for(@user)}")
      end
    rescue ActiveRecord::RecordNotUnique
      # Unique index on (operator_id, lower(email)) — a concurrent signup
      # slipped past the validation; surface it like a validation failure.
      context.fail!(message: "Unable to sign up. Please review errors. Email has already been taken")
    end

    context.notifiable = @user

    result = CreateStripeCustomer.call(user: @user, location: @user.original_location)

    if !result.success?
      # SELF-signups must not leave a half-created account behind — the
      # person's retry hits the unique-email check and gets "Email has
      # already been taken" forever. ADMIN-created members are kept even when
      # the Stripe step fails (staff/comp members may never pay; the customer
      # is created lazily at first purchase) — the admin still sees the error.
      # A claimed stub is never destroyed — the transaction rollback restores it.
      @user.destroy if @user.persisted? && !context.admin_created && !context.claimed
      context.fail!(message: result.message)
    end
  end

  def claimable_stub
    email = context.params[:email].to_s.downcase.strip
    return nil if email.blank?

    stub = context.operator.users.find_by("lower(email) = ?", email)
    return nil if stub.nil?
    return nil if stub.email_confirmed? || stub.approved? || stub.terms_accepted_at.present?
    return nil if User::STAFF_ROLES.include?(stub.role)
    return nil if stub.subscriptions.exists? || stub.day_passes.exists? || stub.day_pass_bundles.exists?

    stub
  end
end
