namespace :automations do
  desc "Run all enabled automated workflows + daily operator notifications"
  task run: :environment do
    AutomatedWorkflowsJob.perform_later
    # The office-vacancy push rides this same daily Heroku Scheduler entry — no
    # separate schedule needed. Its "freed in the last day" dedup is built for a
    # daily cadence. `offices:notify_vacancies` remains for a standalone/manual run.
    OfficeVacancyNotificationJob.perform_later
  end
end
