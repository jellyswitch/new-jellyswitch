require "mail_hatch"

Rails.application.config.active_job.custom_serializers << MailHatch::MailHatchSerializer
