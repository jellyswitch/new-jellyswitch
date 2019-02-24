module HostValidator
  def validate_host
    raise "No @subdomain defined" unless @subdomain.present?
  end
end