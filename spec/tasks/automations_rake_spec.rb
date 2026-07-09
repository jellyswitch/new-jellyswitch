require "rails_helper"
require "rake"

RSpec.describe "automations:run rake task" do
  before do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/automations", [Rails.root.join("lib").to_s])
    Rake::Task.define_task(:environment) # no-op; the app is already loaded
  end

  it "enqueues the automations job AND the daily office-vacancy push" do
    expect { Rake::Task["automations:run"].invoke }
      .to have_enqueued_job(AutomatedWorkflowsJob)
      .and have_enqueued_job(OfficeVacancyNotificationJob)
  end
end
