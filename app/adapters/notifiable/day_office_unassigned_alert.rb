module Notifiable
  # Staff-facing side of a Day Office burn that found no free room (ADR 0026,
  # decision #4) — the WALK-IN variant: someone is in the building right now on
  # a burned pass with no room. Staff need to either free/reassign a room or
  # restore the pass. Wraps the DayPass and deep-links to the member, where both
  # of those actions live (T12's reassign/restore endpoints).
  #
  # T16 (mobile): the "user" deep-link type must route to MemberDetail keyed on
  # resource_id. Until that mapping lands, tapping this push just opens the app
  # — which is the intended fallback, not a bug, but it does mean the admin has
  # to find the member by hand.
  #
  # Deliberately NOT gated on operator.day_pass_notifications? — that toggle
  # mutes the routine "someone bought a day pass" announcement. This is an
  # exception that needs a human, so it follows Notifiable::OfficeVacancy
  # (ungated admin alert) instead.
  class DayOfficeUnassignedAlert < Notifiable::Default
    include Notifiable::DayOfficeDayLabel

    private

    # Push only. The admin feed renders a fixed set of blob types; inventing
    # one here would risk an unrenderable card (see the orphaned-blob 500).
    def create_feed_item; end

    def deep_link_data
      { type: "user", resource_id: user_id, path: "/users/#{user_id}" }
    end

    def should_send_notification?
      true
    end

    def message
      "#{member_name} arrived on a Day Office pass but no office was free — " \
        "reassign a room or restore the pass"
    end

    def member_name
      user&.name.presence || "A member"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
