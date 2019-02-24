class ApplicationMailer < ActionMailer::Base
  default from: 'from@example.com'
  layout 'mailer'
  include HostValidator

  protected

  def default_url_options
    {
      host: "#{@subdomain}.#{ENV['HOST']}"
    }
  end
end
