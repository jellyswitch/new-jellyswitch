require "rails_helper"

RSpec.describe ReportMailer, type: :mailer do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:csv_data) { "Name,Email\nJohn,john@example.com\n" }
  let(:recipient) { "admin@example.com" }

  describe "#member_csv_export" do
    let(:mail) { described_class.member_csv_export(operator, location, csv_data, recipient) }

    it "sends to the correct recipient" do
      expect(mail.to).to eq([recipient])
    end

    it "has the correct subject" do
      expect(mail.subject).to eq("Your member CSV export is ready")
    end

    it "attaches the CSV file" do
      expect(mail.attachments.count).to eq(1)
      expect(mail.attachments.first.filename).to eq("Jellyswitch-Member-Data.csv")
      expect(mail.attachments.first.body.decoded.gsub("\r\n", "\n")).to eq(csv_data)
    end

    context "without a location" do
      let(:mail) { described_class.member_csv_export(operator, nil, csv_data, recipient) }

      it "uses operator name in the body" do
        expect(mail.body.encoded).to include(operator.name)
      end
    end
  end
end
