require "rails_helper"

RSpec.describe Office, type: :model do
  describe "associations" do
    it { should belong_to(:operator) }
    it { should belong_to(:location) }
    it { should have_many(:office_leases).dependent(:destroy) }
    it { should have_one_attached(:lease) }
    it { should have_one_attached(:photo) }
  end

  describe "scopes" do
    let!(:visible_office) { create(:office, visible: true) }
    let!(:archived_office) { create(:office, visible: false) }

    describe ".visible" do
      it "returns visible offices" do
        expect(Office.visible).to include(visible_office)
        expect(Office.visible).not_to include(archived_office)
      end
    end

    describe ".archived" do
      it "returns archived offices" do
        expect(Office.archived).to include(archived_office)
        expect(Office.archived).not_to include(visible_office)
      end
    end
  end

  describe "class methods" do
    describe ".available_for_lease" do
      let!(:office_without_lease) { create(:office, visible: true) }
      let!(:office_with_expired_lease) do
        office = create(:office, visible: true)
        create(:office_lease, office: office, end_date: 1.day.ago)
        office
      end
      let!(:office_with_active_lease) do
        office = create(:office, visible: true)
        create(:office_lease, office: office, start_date: 1.month.ago, end_date: 1.month.from_now)
        office
      end

      it "returns offices without leases or with expired leases" do
        available = Office.available_for_lease
        expect(available).to include(office_without_lease, office_with_expired_lease)
        expect(available).not_to include(office_with_active_lease)
      end
    end

    describe ".upcoming_renewals" do
      let!(:office_with_upcoming_renewal) do
        office = create(:office, visible: true)
        create(:office_lease, office: office, end_date: 30.days.from_now)
        office
      end
      let!(:office_with_far_renewal) do
        office = create(:office, visible: true)
        create(:office_lease, office: office, end_date: 90.days.from_now)
        office
      end

      it "returns offices with leases ending within specified days" do
        renewals = Office.upcoming_renewals(45)
        expect(renewals).to include(office_with_upcoming_renewal)
        expect(renewals).not_to include(office_with_far_renewal)
      end
    end

    describe ".occupied" do
      let!(:occupied_office) do
        office = create(:office, visible: true)
        create(:office_lease, office: office, start_date: 1.month.ago, end_date: 1.month.from_now)
        office
      end
      let!(:vacant_office) { create(:office, visible: true) }

      it "returns offices with active leases" do
        expect(Office.occupied).to include(occupied_office)
        expect(Office.occupied).not_to include(vacant_office)
      end
    end
  end

  describe "instance methods" do
    let(:office) { create(:office) }

    describe "#has_active_lease?" do
      it "returns true when office has active lease" do
        create(:office_lease, office: office, start_date: 1.month.ago, end_date: 1.month.from_now)
        expect(office.has_active_lease?).to be true
      end

      it "returns false when office has no active lease" do
        expect(office.has_active_lease?).to be false
      end
    end

    describe "#available?" do
      it "returns true when office has no active lease" do
        expect(office.available?).to be true
      end

      it "returns false when office has active lease" do
        create(:office_lease, office: office, start_date: 1.month.ago, end_date: 1.month.from_now)
        expect(office.available?).to be false
      end
    end

    describe "#active_leases" do
      it "returns active leases for the office" do
        active_lease = create(:office_lease, office: office, start_date: 1.month.ago, end_date: 1.month.from_now)
        expired_lease = create(:office_lease, office: office, start_date: 2.months.ago, end_date: 1.month.ago)

        expect(office.active_leases).to include(active_lease)
        expect(office.active_leases).not_to include(expired_lease)
      end
    end

    describe "#has_photo?" do
      it "returns true when photo is attached" do
        office.photo.attach(
          io: StringIO.new("dummy image"),
          filename: "office.jpg",
          content_type: "image/jpeg"
        )
        expect(office.has_photo?).to be true
      end

      it "returns false when photo is not attached" do
        expect(office.has_photo?).to be false
      end
    end

    describe "photo variants" do
      before do
        office.photo.attach(
          io: StringIO.new("dummy image"),
          filename: "office.jpg",
          content_type: "image/jpeg"
        )
      end

      it "generates square_photo variant" do
        expect(office.photo).to receive(:variant).with(auto_orient: true, resize: "300x300")
        office.square_photo
      end

      it "generates card_photo variant" do
        expect(office.photo).to receive(:variant).with(auto_orient: true, resize: "x200")
        office.card_photo
      end

      it "generates thumbnail variant" do
        expect(office.photo).to receive(:variant).with(resize: "180x180", auto_orient: true)
        office.thumbnail
      end
    end
  end
end