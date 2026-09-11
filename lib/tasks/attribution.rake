# frozen_string_literal: true

# One-time (idempotent) backfill for the Conversions report:
#   1. stamp first-touch attribution on every user from their earliest visit
#   2. reconstruct historical Conversion rows from the records that already
#      exist (signups, tour/chat leads, charged day passes, bundles, paid
#      reservations, paid subscriptions, office leases)
#
#   heroku run rails attribution:backfill              # all operators
#   heroku run rails attribution:backfill OPERATOR=243 # one operator
#
# Safe to re-run: users already stamped are skipped, conversions are unique
# per (subject, kind). Backfilled rows carry surface="backfill" so the report
# can tell "self-serve" (unknown for history) from live-tracked rows.
namespace :attribution do
  desc "Re-run the classifier on every user's stored first visit and resync conversion snapshots (after classifier changes)"
  task restamp: :environment do
    ActiveRecord::Base.logger = nil
    operators = ENV["OPERATOR"].present? ? Operator.where(id: ENV["OPERATOR"]) : Operator.all
    operators.find_each do |operator|
      changed = 0
      User.unscoped.where(operator_id: operator.id).find_each do |user|
        before = [user.acquisition_channel, user.acquisition_referrer]
        Attribution::AssignFirstTouch.call(user, surface: "web", force: true)
        user.reload
        next if before == [user.acquisition_channel, user.acquisition_referrer]
        changed += 1
        Conversion.unscoped.where(user_id: user.id).update_all(
          channel: user.acquisition_channel, source: user.acquisition_source, medium: user.acquisition_medium,
          campaign: user.acquisition_campaign, referrer_domain: user.acquisition_referrer,
          landing_page: user.acquisition_landing_page,
        )
      end
      puts "[attribution] #{operator.name} (#{operator.id}): restamped #{changed} users"
    end
  end

  desc "Stamp first-touch attribution on users and rebuild historical conversions"
  task backfill: :environment do
    ActiveRecord::Base.logger = nil
    operators = ENV["OPERATOR"].present? ? Operator.where(id: ENV["OPERATOR"]) : Operator.all
    since = ENV["SINCE"].present? ? Date.parse(ENV["SINCE"]) : Date.new(2019, 1, 1)

    operators.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        stamped = 0
        User.unscoped.where(operator_id: operator.id, acquired_at: nil).find_each do |user|
          Attribution::AssignFirstTouch.call(user, surface: "web")
          stamped += 1
        end

        counts = Hash.new(0)
        add = ->(kind, user, subject, amount, location, at) do
          next if at.nil? || at < since
          row = Conversion.record(kind: kind, operator: operator, location: location, user: user,
                                  subject: subject, amount_cents: amount, surface: "backfill",
                                  occurred_at: at)
          counts[kind] += 1 if row&.previously_new_record?
        end

        User.unscoped.where(operator_id: operator.id).find_each do |u|
          add.call("signup", u, u, 0, u.original_location, u.created_at)
        end

        Activity.unscoped.where(operator_id: operator.id, kind: %w[tour_request chat]).find_each do |a|
          kind = a.kind == "chat" ? "chat_lead" : "tour_request"
          loc = a.subject.is_a?(Location) ? a.subject : a.user&.original_location
          add.call(kind, a.user, a, 0, loc, a.occurred_at)
        end

        DayPass.unscoped.where(operator_id: operator.id).where(complimentary: [false, nil])
               .where("stripe_charge_id IS NOT NULL OR invoice_id IS NOT NULL")
               .includes(:day_pass_type, :user).find_each do |dp|
          add.call("day_pass", dp.user, dp, dp.day_pass_type&.amount_in_cents, dp.location || dp.user&.original_location, dp.created_at)
        end

        DayPassBundle.unscoped.where(operator_id: operator.id).includes(:day_pass_type, :user).find_each do |b|
          next if b.day_pass_type&.amount_in_cents.to_i <= 0
          add.call("day_pass_bundle", b.user, b, b.day_pass_type.amount_in_cents, b.location, b.purchased_at || b.created_at)
        end

        room_ids = Room.unscoped.where(operator_id: operator.id).pluck(:id)
        Reservation.unscoped.where(room_id: room_ids, cancelled: false)
                   .where("paid = true OR captured_amount_in_cents > 0")
                   .includes(:room, :user).find_each do |r|
          amount = r.captured_amount_in_cents.to_i
          amount = ((r.room.hourly_rate_in_cents.to_i / 60.0) * r.minutes.to_i).round if amount.zero? && r.paid
          next if amount <= 0
          add.call("room_reservation", r.user, r, amount, r.room.location, r.created_at)
        end

        plan_ids = Plan.unscoped.where(operator_id: operator.id).where("amount_in_cents > 0").pluck(:id)
        Subscription.unscoped.where(plan_id: plan_ids, subscribable_type: "User").includes(:plan).find_each do |s|
          user = User.unscoped.find_by(id: s.subscribable_id)
          add.call("membership", user, s, s.plan.amount_in_cents, s.plan.location || user&.original_location, s.created_at)
        end

        OfficeLease.unscoped.where(operator_id: operator.id).includes(:organization, subscription: :plan).find_each do |l|
          plan = l.subscription&.plan
          next unless plan
          owner = l.organization&.owner
          add.call("office_lease", owner, l, plan.amount_in_cents, l.location, l.created_at)
        end

        puts "[attribution] #{operator.name} (#{operator.id}): stamped #{stamped} users; new conversions #{counts.inspect}"
      end
    end
  end
end
