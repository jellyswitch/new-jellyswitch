class NormalizeBundleMeetingMinutesToPerDay < ActiveRecord::Migration[7.2]
  # Bundle day-pass types stored the WHOLE pack's meeting-minute pool
  # (180 × pack size: 2-packs 360, 5-packs 900), but the overage math has
  # always applied the value PER redeemed day — so a bundle holder got 6h/15h
  # of free meeting rooms EVERY day (Alma Quiroga, 2026-08-06: 328 minutes in
  # one day, zero overage). ADR 0025: included_meeting_room_minutes on a
  # bundle type is the DAILY allowance, operator-set. Normalize exactly the
  # 180 × quantity pool pattern; custom values are left for operator review.
  def up
    DayPassType.unscoped
               .where("quantity > 1")
               .where("included_meeting_room_minutes = quantity * 180")
               .update_all(included_meeting_room_minutes: 180)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
