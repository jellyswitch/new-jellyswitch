
module HostValidator
  def validate_host
    raise "No @operator defined" unless @operator.present?
  end

  protected

  # Merge onto the app-level options rather than replacing them. Returning a
  # bare hash here silently dropped everything configured in application.rb /
  # production.rb -- most recently `protocol: 'https'`, so this mailer kept
  # emitting http:// links after every other mailer had been fixed. An instance
  # method fully overrides the config hash, so anything not merged is lost.
  def default_url_options
    super.merge(host: "#{@operator.subdomain}.#{ENV['HOST']}")
  end

  def mail(headers = {}, &block)
    validate_host
    if @operator.email_enabled?
      super(headers.merge(default_options), &block)
    else
      false
    end
  end

  def default_options
    {
      from: "#{@operator.name} <noreply@#{@operator.subdomain}.#{ENV['HOST']}>"
    }
  end
end