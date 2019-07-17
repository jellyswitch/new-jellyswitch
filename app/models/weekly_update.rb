# == Schema Information
#
# Table name: weekly_updates
#
#  id            :bigint(8)        not null, primary key
#  blob          :jsonb
#  previous_blob :jsonb
#  week_end      :datetime
#  week_start    :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operator_id   :integer
#

class WeeklyUpdate < ApplicationRecord
  belongs_to :operator
  acts_as_tenant :operator

  store_accessor :blob, :day_passes, :checkins, :new_active_members, :new_free_members, 
    :rooms, :paid_invoices, :unpaid_invoices, :revenue, :reservations, 
    :active_member_count, :free_member_count, :active_lease_member_count,
    :management_notes, :questions, :unanswered_questions, :admins

  store_accessor :previous_blob, :prev_day_passes, :prev_checkins, :prev_new_active_members, :prev_new_free_members, 
  :prev_rooms, :prev_paid_invoices, :prev_unpaid_invoices, :prev_revenue, :prev_reservations, 
  :prev_active_member_count, :prev_free_member_count, :prev_active_lease_member_count,
  :prev_management_notes, :prev_questions, :prev_unanswered_questions, :prev_admins

  def self.from_weekly_reports(report, previous_report)
    w = from_weekly_report(report)

    temp_w = from_weekly_report(previous_report)
    w.previous_blob = temp_w.blob
    w
  end

  def self.from_weekly_report(report)
    w = WeeklyUpdate.new
    w.blob = {} 
    
    w.week_start = report.week_start
    w.week_end = report.week_end
    w.operator_id = report.operator.id

    w.day_passes = report.day_passes
    w.checkins = report.checkins
    
    w.new_active_members = report.new_active_members
    w.new_free_members = report.new_free_members

    w.active_member_count = report.active_member_count
    w.free_member_count = report.free_member_count
    w.active_lease_member_count = report.active_lease_member_count

    w.reservations = report.reservations

    w.rooms = report.rooms

    w.paid_invoices = report.paid_invoices.map(&:id)
    w.unpaid_invoices = report.unpaid_invoices.map(&:id)

    w.management_notes = report.management_notes.map(&:id)
    w.questions = report.questions.map(&:id)
    w.unanswered_questions = report.unanswered_questions.map(&:id)

    w.revenue = report.revenue

    w.admins = report.admins.map(&:id)

    w
  end

  def admins
    blob["admins"].map do |admin_id|
      User.find(admin_id)
    end
  end

  def prev_admins
    previous_blob["admins"].map do |admin_id|
      User.find(admin_id)
    end
  end
end
