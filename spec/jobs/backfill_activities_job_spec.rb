require "rails_helper"

RSpec.describe BackfillActivitiesJob, type: :job do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }

  describe "#perform" do
    context "with fresh source data and no prior activities" do
      let!(:room) { create(:room, location: location) }
      let!(:reservation) { create(:reservation, user: user, room: room) }
      let!(:checkin) { create(:checkin, user: user, location: location) }
      let!(:day_pass) { create(:day_pass, user: user, operator: operator) }
      let!(:lead) { create(:lead, user: user, operator: operator) }
      let!(:lead_note) { create(:lead_note, lead: lead, user: user) }

      before do
        # Simulate "pre-Phase-1" world: source data exists but no activities yet.
        Activity.delete_all
      end

      it "logs one Activity per source record, all scoped to this operator" do
        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.where(subject: reservation, kind: "reservation").count).to eq(1)
        expect(Activity.where(subject: checkin, kind: "checkin").count).to eq(1)
        expect(Activity.where(subject: day_pass, kind: "day_pass").count).to eq(1)
        expect(Activity.where(subject: lead_note, kind: "note").count).to eq(1)
        expect(Activity.where(subject: user, kind: "signup").count).to eq(1)
      end

      it "uses the source record's created_at as occurred_at" do
        reservation.update_columns(created_at: 5.days.ago)

        BackfillActivitiesJob.perform_now(operator.id)
        activity = Activity.where(subject: reservation, kind: "reservation").first

        expect(activity.occurred_at).to be_within(1.second).of(reservation.created_at)
      end

      it "skips records older than the 'since' window" do
        other_room = create(:room, location: location)
        old_reservation = create(:reservation, user: user, room: other_room, datetime_in: 3.years.ago)
        old_reservation.update_columns(created_at: 3.years.ago)

        Activity.delete_all
        BackfillActivitiesJob.perform_now(operator.id, since: 2.years.ago)

        expect(Activity.where(subject: old_reservation)).not_to exist
        expect(Activity.where(subject: reservation)).to exist
      end

      it "does not touch other operators' data" do
        other_operator = create(:operator)
        other_location = create(:location, operator: other_operator)
        other_room = create(:room, location: other_location)
        other_user = create(:user, operator: other_operator)
        other_reservation = create(:reservation, user: other_user, room: other_room)
        Activity.delete_all

        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.where(subject: other_reservation)).not_to exist
        expect(Activity.where(subject: reservation)).to exist
      end

      it "updates operator.last_activities_backfilled_at" do
        expect {
          BackfillActivitiesJob.perform_now(operator.id)
        }.to change { operator.reload.last_activities_backfilled_at }.from(nil)
      end
    end

    context "idempotency" do
      let!(:room) { create(:room, location: location) }
      let!(:reservation) { create(:reservation, user: user, room: room) }
      let!(:lead) { create(:lead, user: user, operator: operator) }
      let!(:lead_note) { create(:lead_note, lead: lead, user: user) }

      it "is a no-op when activities already exist for all source records" do
        # Phase 1.3 callbacks have already populated activities. Verify backfill
        # writes nothing on top.
        existing_count = Activity.count
        expect(existing_count).to be > 0

        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.count).to eq(existing_count)
      end

      it "creates no duplicates when run twice" do
        Activity.delete_all
        BackfillActivitiesJob.perform_now(operator.id)
        after_first_run = Activity.count

        expect {
          BackfillActivitiesJob.perform_now(operator.id)
        }.not_to change(Activity, :count)

        expect(Activity.count).to eq(after_first_run)
      end
    end

    context "subscriptions" do
      let!(:active_sub) do
        create(:subscription, subscribable: user, billable: user, active: true)
      end
      let!(:ended_sub) do
        sub = create(:subscription, subscribable: user, billable: user, active: true)
        sub.update_columns(active: false, updated_at: 1.day.ago)
        sub
      end

      before { Activity.delete_all }

      it "backfills :subscription_started for both active and ended subs" do
        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.where(subject: active_sub, kind: "subscription_started")).to exist
        expect(Activity.where(subject: ended_sub, kind: "subscription_started")).to exist
      end

      it "backfills :subscription_ended only for inactive subs" do
        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.where(subject: ended_sub, kind: "subscription_ended")).to exist
        expect(Activity.where(subject: active_sub, kind: "subscription_ended")).not_to exist
      end
    end

    context "invoices" do
      let!(:paid_invoice) do
        create(:invoice, billable: user, operator: operator, status: "paid")
      end
      let!(:uncollectible_invoice) do
        create(:invoice, billable: user, operator: operator, status: "uncollectible")
      end
      let!(:open_invoice) do
        create(:invoice, billable: user, operator: operator, status: "open")
      end

      before { Activity.delete_all }

      it "logs :payment_succeeded for paid and :payment_failed for uncollectible" do
        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.where(subject: paid_invoice, kind: "payment_succeeded")).to exist
        expect(Activity.where(subject: uncollectible_invoice, kind: "payment_failed")).to exist
      end

      it "does not log for open invoices" do
        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.where(subject: open_invoice)).not_to exist
      end

      it "does not log for Organization-billed invoices" do
        org_invoice = create(:invoice, operator: operator, status: "paid") # factory default is Org
        Activity.delete_all
        BackfillActivitiesJob.perform_now(operator.id)

        expect(Activity.where(subject: org_invoice)).not_to exist
      end
    end
  end
end
