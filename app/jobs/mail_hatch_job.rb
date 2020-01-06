class MailHatchJob < ApplicationJob
  queue_as :mailers

  def perform(mail_hatch, method_name, args)
    puts "PERFORM"
    mail_hatch.send(method_name, args)
  end
end