require "rails_helper"
require "sidekiq/testing"

RSpec.describe "Sidekiq DST Transition Tests" do
  before do
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all
    Time.zone = "Pacific Time (US & Canada)"
  end

  after do
    Sidekiq::Testing.inline!
  end

  let(:spring_forward_date) { Time.zone.local(2024, 3, 10) }
  let(:fall_back_date) { Time.zone.local(2024, 11, 3) }

  class DstTestJob
    include Sidekiq::Worker
    sidekiq_options queue: "default"

    def perform
      Rails.logger.info "DstTestJob performed"
    end
  end

  describe "Spring Forward Transition" do
    it "schedules jobs correctly during spring forward" do
      Timecop.freeze(spring_forward_date.change(hour: 1, min: 30)) do
        expect {
          DstTestJob.perform_at(Time.zone.now + 1.hour)
        }.to change { Sidekiq::Queues["default"].size }.by(1)

        job = Sidekiq::Queues["default"].first
        scheduled_time = Time.at(job["at"]).in_time_zone("Pacific Time (US & Canada)")
        expect(scheduled_time.hour).to eq(3)
        expect(scheduled_time.min).to eq(30)
      end
    end
  end

  describe "Fall Back Transition" do
    it "schedules jobs correctly during fall back" do
      Timecop.freeze(fall_back_date.change(hour: 1, min: 30)) do
        expect {
          DstTestJob.perform_at(Time.zone.now + 45.minutes)
        }.to change { Sidekiq::Queues["default"].size }.by(1)

        job = Sidekiq::Queues["default"].first
        scheduled_time = Time.at(job["at"]).in_time_zone("Pacific Time (US & Canada)")

        expect(scheduled_time.hour).to eq(1)
        expect(scheduled_time.min).to eq(15)
      end
    end
  end
end
