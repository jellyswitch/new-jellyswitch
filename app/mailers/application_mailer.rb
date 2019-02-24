class ApplicationMailer < ActionMailer::Base
  default from: 'from@example.com'
  layout 'mailer'
  include HostValidator

  protected

  def default_url_options
    {
      host: "#{@operator.subdomain}.#{ENV['HOST']}"
    }
  end

  def mail(headers = {}, &block)
    validate_host
    if @operator.email_enabled?
      super(headers, &block)
    else
      false
    end
  end
end
