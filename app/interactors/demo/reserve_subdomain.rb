class Demo::ReserveSubdomain
  include Interactor

  def call
    operator = context.operator

    if Subdomain.unreserved.count < 1
      context.fail!(message: "No more subdomains available.")
    end

    subdomain = Subdomain.unreserved.first

    ActiveRecord::Base.transaction do
      operator.subdomain = subdomain.subdomain
      subdomain.in_use = true

      operator.save!
      subdomain.save!
    end
  end
end