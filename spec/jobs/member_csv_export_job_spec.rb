require "rails_helper"

RSpec.describe MemberCsvExportJob, type: :job do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  it "generates CSV and sends email" do
    csv_data = "Name,Email\nJohn,john@example.com\n"
    report = instance_double(Jellyswitch::Report, member_csv: csv_data)
    allow(Jellyswitch::Report).to receive(:new).with(operator, location).and_return(report)

    mailer = double(deliver_now: true)
    allow(ReportMailer).to receive(:member_csv_export)
      .with(operator, location, csv_data, "admin@example.com")
      .and_return(mailer)

    described_class.perform_now(operator.id, location.id, "admin@example.com")

    expect(Jellyswitch::Report).to have_received(:new).with(operator, location)
    expect(ReportMailer).to have_received(:member_csv_export)
      .with(operator, location, csv_data, "admin@example.com")
    expect(mailer).to have_received(:deliver_now)
  end

  it "resolves CSV constant within Jellyswitch::Report namespace" do
    report = Jellyswitch::Report.new(operator, location)
    csv_data = report.member_csv
    expect(csv_data).to be_a(String)
    expect(csv_data).to include("Name")
  end

  it "works without a location" do
    csv_data = "Name,Email\n"
    report = instance_double(Jellyswitch::Report, member_csv: csv_data)
    allow(Jellyswitch::Report).to receive(:new).with(operator, nil).and_return(report)

    mailer = double(deliver_now: true)
    allow(ReportMailer).to receive(:member_csv_export)
      .with(operator, nil, csv_data, "admin@example.com")
      .and_return(mailer)

    described_class.perform_now(operator.id, nil, "admin@example.com")

    expect(Jellyswitch::Report).to have_received(:new).with(operator, nil)
  end
end
