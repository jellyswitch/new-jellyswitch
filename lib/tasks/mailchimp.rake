namespace :mailchimp do
  desc "Sync all members to Mailchimp"
  task sync: :environment do
    MailchimpSyncJob.perform_later
  end
end
