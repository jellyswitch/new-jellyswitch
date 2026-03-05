
class MemberCsvExportJob < ApplicationJob
  queue_as :default

  def perform(operator_id, location_id, user_email)
    operator = Operator.find(operator_id)
    location = location_id.present? ? Location.find(location_id) : nil
    csv_data = Jellyswitch::Report.new(operator, location).member_csv
    ReportMailer.member_csv_export(operator, location, csv_data, user_email).deliver_now
  end
end
