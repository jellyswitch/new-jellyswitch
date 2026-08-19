module LandingHelper
  def landing_redirect
    if logged_in? && current_location.present?
      if admin? || community_manager? || general_manager?
        if current_tenant.onboarded? || current_tenant.skip_onboarding?
          redirect_to feed_items_path
        else
          redirect_to new_operator_onboarding_path
        end
      else
        if current_user.allowed_in?(current_location)
          if approved?
            if current_tenant.checkin_required? && !current_user.checked_in?(current_location)
              redirect_to required_checkins_path
            else
              redirect_to home_path
            end
          else
            # Unapproved but has access — show wait page with progress
            redirect_to wait_path
          end
        else
          if pending?
            redirect_to activate_path
          else
            # Both unapproved new signups AND approved non-members land here
            redirect_to choose_path
          end
        end
      end
    end
  end

  def home_redirect
    if current_location.present? && (current_user&.allowed_in?(current_location) || (!policy(:payment).enabled? && current_tenant.subdomain != "southlakecoworking"))
      if !approved? && !admin?
        # Unapproved users with pending subscription → wait for approval
        # Unapproved users without → let them choose a plan
        if current_user.subscriptions.pending.any?
          redirect_to wait_path
        else
          redirect_to choose_path
        end
        return
      else
        if !admin? && !always_has_access? && current_tenant.checkin_required? && !current_user.checked_in?(current_location)
          redirect_to required_checkins_path
        else
          render :home
        end
      end
    else
      if logged_in?
        if pending?
          redirect_to activate_path
        else
          if hit_membership_limit?
            redirect_to upgrade_path
          else
            redirect_to choose_path
          end
        end
      else
        # they're logged out
        redirect_to root_path
      end
    end
  end

  # Picks the "space host" surfaced in the choose-page nudge bubble and in
  # the auto-greeting chat thread. Resolution order:
  #
  #   1. `location.space_host` — explicit per-location override. Operators
  #      set this to designate a specific on-site host so the bubble doesn't
  #      default to whoever happens to be the operator's founder.
  #   2. General manager whose current_location_id matches this location.
  #   3. Oldest admin on the operator (last-resort fallback).
  #
  # Returns nil when none of those exist.
  # Never returns an archived user: the host authors greeting replies, and
  # FeedbackReply refuses archived authors (#731) — an archived configured
  # host (Cowork Tahoe pointed at a long-archived admin account) turned every
  # new member's first message into a 500. An archived host falls through to
  # the live-GM/admin chain like no host was configured at all.
  def space_host_for(location)
    return nil unless location

    configured = location.space_host_id.present? ? location.space_host : nil
    return configured if configured && !configured.archived?

    gm = location.operator.users.visible
                 .where(role: User::GENERAL_MANAGER, current_location_id: location.id)
                 .order(:created_at).first
    gm || location.operator.users.visible.where(role: User::ADMIN).order(:created_at).first
  end

  # All of the member's feedback threads with at least one unread admin reply,
  # ordered most-recent-first. Drives the global banner, the nudge bubble's
  # "reply waiting" variant, and the my_feedback list page.
  def unread_admin_threads_for(user)
    return [] unless user

    user.member_feedbacks
        .includes(:feedback_replies)
        .select { |f| f.has_unread_replies? && f.feedback_replies.any?(&:from_admin?) }
        .sort_by { |f| -(f.feedback_replies.last&.created_at&.to_i || 0) }
  end

  private

  def always_has_access?
    current_user.has_building_access_lease? || current_user.always_allow_building_access?
  end
end
