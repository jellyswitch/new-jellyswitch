require "mail_hatch"

Rails.application.config.active_job.custom_serializers << MailHatchSerializer
