
class ReportMailer < ApplicationMailer
  def member_csv_export(operator, location, csv_data, recipient_email)
    @location_name = location&.name || operator.name
    attachments["Jellyswitch-Member-Data.csv"] = csv_data
    mail(to: recipient_email, subject: "Your member CSV export is ready")
  end
end
