class ActivityLogger
  def self.log(user:, kind:, operator: nil, subject: nil, payload: nil, occurred_at: nil)
    operator ||= derive_operator(subject)
    raise ArgumentError, "operator required (pass explicitly or via a subject responding to #operator)" if operator.nil?

    payload = derive_payload(subject) if payload.nil?

    Activity.create!(
      user: user,
      operator: operator,
      kind: kind.to_s,
      subject: subject,
      payload: payload || {},
      occurred_at: occurred_at || Time.current,
    )
  end

  def self.derive_operator(subject)
    return nil if subject.nil?
    return subject.operator if subject.respond_to?(:operator) && subject.operator
    return subject.location.operator if subject.respond_to?(:location) && subject.location.respond_to?(:operator) && subject.location.operator
    nil
  end
  private_class_method :derive_operator

  def self.derive_payload(subject)
    return {} if subject.nil?
    return subject.to_activity_payload if subject.respond_to?(:to_activity_payload)
    {}
  end
  private_class_method :derive_payload
end
