class Api::V1::Admin::FeedController < Api::V1::Admin::BaseController
  def index
    # Order by recent ACTIVITY, not creation. A member's in-thread feedback
    # reply upserts the existing feed card and bumps its updated_at (see
    # FeedItemCreator.upsert_feedback_feed_item), so a freshly-replied
    # conversation must float back to the top. Ordering by created_at left the
    # reply buried at the thread's original position — the web feed already
    # sorts by updated_at (FeedItemsHelper#generic_feed_items), so this also
    # brings the mobile feed to parity with the dashboard.
    items = FeedItem.where(operator: current_tenant)
                    .includes(:user, :feed_item_comments, :rich_text_text)
                    .order(updated_at: :desc)

    items = apply_filter(items, params[:filter]) if params[:filter].present?

    # Per-operator toggles — hide types the operator has muted.
    op = current_tenant
    hidden_types = []
    hidden_types << 'reservation' unless op.try(:reservation_notifications)
    hidden_types << 'paid-room-reservation' unless op.try(:paid_room_reservation_notifications)
    hidden_types << 'day-pass' unless op.try(:day_pass_notifications)
    hidden_types << 'subscription' unless op.try(:membership_notifications)
    hidden_types << 'new-user' unless op.try(:signup_notifications)
    hidden_types << 'checkin' unless op.try(:checkin_notifications)
    hidden_types << 'feedback' unless op.try(:member_feedback_notifications)
    hidden_types << 'refund' unless op.try(:refund_notifications)
    hidden_types << 'post' unless op.try(:post_notifications)
    items = items.where.not("blob->>'type' IN (?)", hidden_types) if hidden_types.any?

    items = items.offset(params[:offset].to_i).limit(30)

    render json: items.map { |fi| feed_item_json(fi) }
  end

  def create
    body = params[:body]
    # Persist body in three places so the note renders everywhere:
    #   - blob['body']  — what this serializer (and the mobile FeedScreen) reads
    #   - blob['text']  — what web-created notes use; keeps stripped plain-text
    #                     parity with FeedItems::Save and any blob['text'] readers
    #   - text (ActionText) — what the web _post_feed_item.html.erb partial
    #                          renders. Without this, mobile-created notes show
    #                          as empty cards on the web dashboard.
    feed_item = FeedItem.new(
      blob: { 'type' => 'post', 'body' => body, 'text' => body, 'user_name' => current_api_user.name },
      operator: current_tenant,
      location: current_location,
      user: current_api_user,
    )
    feed_item.text = body
    feed_item.save!

    # Notify @mentioned STAFF (push); cross-post the note onto any tagged
    # CUSTOMER's record (silent — no push). See ADR 0006.
    notify_mentioned_users(body, feed_item, current_api_user)
    Crm::CrossPostFeedTags.call(text: body, source: feed_item, author: current_api_user)

    render json: feed_item_json(feed_item), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.message)
  end

  # Source for the mobile @mention autocomplete. Returns staff + approved
  # members so notes can tag teammates AND members. The old mobile code built
  # this list by filtering the first page of /admin/members down to admin
  # roles, so any admin past page 1 (and every member) was invisible — that's
  # why "tagging admins was broken." Here the server returns the full list.
  def mentionable_users
    users = current_tenant.users.mentionable.order(:name)
    render json: users.map { |u|
      { id: u.id, name: u.name, email: u.email, role: u.role }
    }
  end

  def comment
    feed_item = FeedItem.find(params[:id])
    body = params[:body]

    comment = feed_item.feed_item_comments.create!(
      comment: body,
      user: current_api_user
    )

    # Notify @mentioned STAFF; cross-post onto tagged CUSTOMERS' records (silent).
    notify_mentioned_users(body, feed_item, current_api_user)
    Crm::CrossPostFeedTags.call(text: body, source: feed_item, author: current_api_user)

    render json: {
      id: comment.id,
      body: comment.comment,
      user_name: comment.user.name,
      created_at: comment.created_at
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.message)
  end

  def destroy
    feed_item = FeedItem.find(params[:id])
    feed_item.destroy

    render json: { success: true }
  end

  private

  def apply_filter(items, filter)
    case filter
    when 'questions'
      items.where("blob->>'body' LIKE '%?%' OR blob->>'subject' LIKE '%?%'")
    when 'activity'
      items.where("blob->>'type' IN (?)", %w[feedback day-pass reservation subscription checkin paid-room-reservation])
    when 'notes'
      items.where("blob->>'type' = ?", 'post')
    when 'financial'
      items.where("blob->>'type' = ? OR expense = ?", 'refund', true)
    else
      items
    end
  end

  # The charge shown on a 'reservation' / 'paid-room-reservation' feed card, in
  # cents (nil = free).
  #
  # Always prefer the LIVE charge — reservation.effective_charge_in_cents — which
  # is the same value the web feed shows: room rate × the full booked duration,
  # plus amenities, and it picks up day-pass/subscription overages and the
  # settled capture. The stored blob['charge_amount_in_cents'] is only a snapshot
  # taken at booking time (reservation.charge_amount); it goes stale after an
  # extension and under-reports overages, so it's used only as a fallback when
  # the reservation row is gone (e.g. deleted) and we can't recompute.
  def reservation_charge_in_cents(fi, res)
    if res
      cents = res.effective_charge_in_cents.to_i
      return cents if cents.positive?
    end

    stored = fi.blob['charge_amount_in_cents']
    stored.present? ? stored.to_i : nil
  rescue => e
    Rails.logger.warn("[feed] reservation charge calc failed for ##{res&.id}: #{e.class}: #{e.message}")
    fi.blob['charge_amount_in_cents'].presence&.to_i
  end

  # Plain-text body for a 'post' (management note), rendered to match the web.
  #
  # Web-created notes stored blob['text'] via strip_tags(html), which keeps HTML
  # entities encoded ("&amp;") and drops block-level line breaks — so the mobile
  # card showed "&amp;" and ran paragraphs together. The full rich text is kept
  # on the FeedItem (has_rich_text :text), so render THAT to plain text:
  # to_plain_text decodes entities and turns <div>/<p>/<br> into newlines. Falls
  # back to the stored blob for the rare note with no rich text.
  def post_body(fi)
    plain = fi.text&.to_plain_text
    return plain if plain.present?

    fi.blob['body'].presence || fi.blob['text']
  end

  def feed_item_json(fi)
    type = fi.blob['type']
    user = fi.user
    # Embed the comments themselves, not just the count. Without this,
    # the mobile FeedScreen shows "1" next to the Reply button but
    # gives admins no way to actually read the reply (tapping Reply
    # opens a compose input rather than a thread view). Bounded list —
    # feed items rarely accumulate more than a handful of comments —
    # so inline is fine.
    comments = fi.feed_item_comments.includes(:user).order(:created_at).map { |c|
      {
        id: c.id,
        body: c.comment,
        author: c.user&.name,
        is_admin: c.user&.admin_or_manager?(fi.location) || false,
        created_at: c.created_at,
      }
    }
    base = {
      id: fi.id,
      type: type,
      user_id: user&.id,
      user_name: fi.blob['user_name'] || user&.name,
      user_approved: user&.approved?,
      created_at: fi.created_at,
      expense: fi.expense,
      comment_count: comments.size,
      comments: comments,
    }

    case type
    when 'subscription'
      sub = Subscription.find_by(id: fi.blob['subscription_id'])
      base.merge(
        action_text: 'became a member',
        plan_name: sub&.plan&.name,
        amount: sub&.plan&.amount_in_cents,
        requires_approval: true,
      )
    when 'day-pass', 'day_pass'
      dp = DayPass.find_by(id: fi.blob['day_pass_id'])
      base.merge(
        action_text: 'bought a day pass',
        day_pass_type: dp&.day_pass_type&.name,
        amount: dp&.day_pass_type&.amount_in_cents,
        day: dp&.day&.strftime("%B %e, %Y"),
        requires_approval: true,
      )
    when 'day-pass-bundle'
      bundle = DayPassBundle.find_by(id: fi.blob['day_pass_bundle_id'])
      base.merge(
        action_text: "bought a #{bundle&.quantity_purchased}-Pack",
        day_pass_type: bundle&.day_pass_type&.name,
        # Flat pack price = the one-time charge (ADR 0009); same field the
        # day-pass item above uses, so feed + revenue always agree.
        amount: bundle&.day_pass_type&.amount_in_cents,
        requires_approval: true,
      )
    when 'reservation'
      res = Reservation.find_by(id: fi.blob['reservation_id'])
      base.merge(
        action_text: 'reserved a room',
        room_name: res&.room&.name,
        when: res&.datetime_in&.strftime("%B %e at %l:%M %p")&.strip,
        duration: res ? "#{res.minutes} min" : nil,
        attendee_count: res&.attendee_count,
        amount: reservation_charge_in_cents(fi, res),
      )
    when 'paid-room-reservation', 'paid_room_reservation'
      res = Reservation.find_by(id: fi.blob['reservation_id'])
      base.merge(
        action_text: 'booked a paid meeting room',
        room_name: res&.room&.name,
        when: res&.datetime_in&.strftime("%B %e at %l:%M %p")&.strip,
        duration: res ? "#{res.minutes} min" : nil,
        attendee_count: res&.attendee_count,
        # Same live calc as the 'reservation' card and the web feed — not the
        # stale booking-time snapshot, which showed only the room's hourly-rate
        # estimate instead of the full booking total.
        amount: reservation_charge_in_cents(fi, res),
        requires_approval: true,
      )
    when 'feedback'
      fb = MemberFeedback.find_by(id: fi.blob['member_feedback_id'])
      base.merge(
        action_text: 'sent a message',
        # Prefer the per-reply text captured in the blob (greeting-first
        # threads leave MemberFeedback#comment blank; the message lives on
        # the FeedbackReply). Fall back to the original comment for legacy
        # new-thread feedback items.
        body: fi.blob['body'].presence || fb&.comment,
        feedback_id: fb&.id,
        rating: fb&.rating,
      )
    when 'checkin'
      checkin = Checkin.find_by(id: fi.blob['checkin_id'])
      base.merge(
        action_text: 'checked in',
        location_name: checkin&.location&.name,
        requires_approval: true,
      )
    when 'refund'
      inv = Invoice.find_by(id: fi.blob['invoice_id'])
      base.merge(
        action_text: 'was issued a refund',
        amount: inv&.amount_due,
        description: inv&.try(:description),
      )
    when 'post'
      base.merge(
        action_text: fi.expense? ? 'posted an expense' : 'posted a note',
        body: post_body(fi),
        amount: fi.expense? ? fi.blob['amount'] : nil,
      )
    when 'membership_cancellation'
      base.merge(action_text: 'canceled their membership', body: fi.blob['text'])
    when 'membership_paused'
      base.merge(action_text: 'paused their membership', body: fi.blob['text'])
    when 'membership_unpaused'
      base.merge(action_text: 'resumed their membership', body: fi.blob['text'])
    when 'membership_updated'
      base.merge(action_text: 'updated their membership', body: fi.blob['text'])
    when 'payment_failed'
      base.merge(action_text: 'had a payment failure', body: fi.blob['text'])
    when 'payment_failed_room_reservation'
      res = Reservation.unscoped.find_by(id: fi.blob['reservation_id'])
      base.merge(
        action_text: 'had a payment failure on a meeting room booking',
        room_name: fi.blob['room_name'] || res&.room&.name,
        when: fi.blob['when'] || res&.datetime_in&.strftime("%B %e at %l:%M %p")&.strip,
        body: fi.blob['reason'],
        requires_approval: true,
      )
    when 'account_deletion'
      base.merge(action_text: 'deleted their account', body: fi.blob['text'])
    when 'demand-miss', 'demand_miss'
      base.merge(action_text: "couldn't find an available room", body: fi.blob['text'])
    when 'new-user', 'new_user'
      base.merge(action_text: 'signed up', requires_approval: true)
    when 'lease_renewal'
      base.merge(action_text: 'has a lease renewal proposal', body: fi.blob['text'])
    when 'weekly-update', 'weekly_update'
      # Auto-generated by the WeeklyUpdateJob — no human actor, so we
      # explicitly nil out user_name (the FeedItem.user is whoever
      # happened to be the admin scope when the job ran, often a
      # long-gone account). Body is a multi-line summary the mobile
      # FeedScreen renders inline.
      wu = WeeklyUpdate.find_by(id: fi.blob['weekly_update_id'])
      if wu
        # wu.revenue is already stored in dollars (paid_invoices.sum(:amount_due)
        # / 100.0). The old code divided by 100 a SECOND time, so $500 showed as
        # $5. Round to whole dollars and add thousands separators.
        revenue_dollars = wu.revenue.to_f.round
        stats = ["Day passes: #{wu.day_passes.to_i}"]
        # Check-ins only mean something where hourly drop-in access is enabled.
        stats << "Check-ins: #{wu.checkins.to_i}" if wu.location&.hourly_enabled?
        stats << "New members: #{wu.new_active_members.to_i}"
        stats << "Revenue: $#{revenue_dollars.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
        # Split paid (charged) vs member (covered) reservations. Older updates
        # predate the split, so fall back to the single total for them.
        if wu.paid_reservations || wu.member_reservations
          stats << "Paid reservations: #{wu.paid_reservations.to_i}"
          stats << "Member reservations: #{wu.member_reservations.to_i}"
        else
          stats << "Reservations: #{wu.reservations.to_i}"
        end
        # Per-room utilization of the business window (6am-6pm Mon-Fri).
        # Updates saved before the field existed stored share-of-reservations
        # instead — skip those rather than mislabel them.
        room_lines = (wu.rooms || []).select { |r| r['utilization'] }
        if room_lines.any?
          stats << "Room usage (6am-6pm, Mon-Fri):"
          room_lines.each do |r|
            stats << "• #{r['name']}: #{(r['utilization'].to_f * 100).round}%"
          end
        end
        stats = stats.join("\n")
        header = "Week of #{wu.week_start&.strftime('%b %-d')} – #{wu.week_end&.strftime('%b %-d, %Y')}"
        base.merge(
          user_name: nil,
          user_id: nil,
          action_text: 'Weekly update',
          body: "#{header}\n\n#{stats}",
          weekly_update_id: wu.id,
        )
      else
        base.merge(user_name: nil, user_id: nil, action_text: 'Weekly update')
      end
    else
      base.merge(
        action_text: type&.gsub('-', ' ')&.gsub('_', ' '),
        body: fi.blob['body'] || fi.blob['text'] || fi.blob['subject'],
      )
    end
  rescue => e
    base.merge(action_text: type, body: fi.blob['text'] || fi.blob['body'])
  end

  def notify_mentioned_users(text, feed_item, sender)
    return if text.blank?
    return unless text.include?("@")

    # Resolve mentions by matching each mentionable user's actual name against
    # "@Name" in the text. This replaces a brittle /@([A-Z][a-z]+...)/ regex
    # that only caught Capitalized single/double names — it silently dropped
    # lowercase, hyphenated, apostrophed, and 3+ word names, and (since it only
    # queried by name) never reached members. The negative lookahead stops
    # "@Jo" from also matching "@John".
    current_tenant.users.mentionable.find_each do |user|
      next if user.name.blank?
      next if user.id == sender.id # Don't notify yourself
      # Only STAFF get a push. Tagged CUSTOMERS are handled by
      # Crm::CrossPostFeedTags (cross-post to their record, NO push) — a member
      # must never be pinged about an internal note discussing them (ADR 0006).
      next unless User::STAFF_ROLES.include?(user.role)
      next unless text.match?(/@#{Regexp.escape(user.name)}(?![[:alnum:]])/)

      # Send push notification
      begin
        if user.ios_token.present?
          ios_notification = IosNotification.new(
            token: user.ios_token,
            bundle_id: user.operator.bundle_id,
            message: "#{sender.name} mentioned you: #{text.truncate(100)}",
            data: { screen: 'Feed' }
          )
          ios_notification.send_notification
        end

        if user.android_token.present?
          # Android FCM push
          Notifiable::Default.new(nil).send_android_notification(
            user,
            "#{sender.name} mentioned you",
            text.truncate(100)
          ) rescue nil
        end
      rescue => e
        Rails.logger.error("Mention notification failed for #{user.email}: #{e.message}")
      end
    end
  rescue => e
    Rails.logger.error("notify_mentioned_users error: #{e.message}")
  end
end
