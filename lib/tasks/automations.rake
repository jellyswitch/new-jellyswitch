namespace :automations do
  desc "Run all enabled automated workflows"
  task run: :environment do
    AutomatedWorkflowsJob.perform_later
  end
end
