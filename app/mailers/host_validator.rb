module HostValidator
  def validate_host
    raise "No @operator defined" unless @operator.present?
  end
end