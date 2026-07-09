namespace :offices do
  desc "Notify operators of freshly-freed offices that have people waiting"
  task notify_vacancies: :environment do
    OfficeVacancyNotificationJob.perform_now
  end
end
