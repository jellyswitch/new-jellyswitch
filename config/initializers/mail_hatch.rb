require "mail_hatch/mail_hatch_serializer"

Rails.application.config.active_job.custom_serializers << MailHatch::MailHatchSerializer
