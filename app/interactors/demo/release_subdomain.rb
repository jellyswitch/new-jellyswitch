class Demo::ReleaseSubdomain
  include Interactor

  def call
    operator = context.operator

    subdomain = Subdomain.find_by(subdomain: operator.subdomain)
    if subdomain.nil?
      context.fail!(message: "No such subdomain: #{operator.subdomain}")
    end

    ActiveRecord::Base.transaction do
      subdomain.in_use = false
      operator.subdomain = "placeholder"

      subdomain.save!
      operator.save!
    end
  rescue Exception => e
    context.fail!(e.message)
  end
end