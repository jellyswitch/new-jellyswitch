class Demo::ReleaseSubdomain
  include Interactor

  def call
    operator = context.operator

    subdomain = Subdomain.find_by(subdomain: operator.subdomain)
    if subdomain.present?

      ActiveRecord::Base.transaction do
        subdomain.in_use = false
        operator.subdomain = "placeholder"

        subdomain.save!
        operator.save!
      end
    end
  rescue Exception => e
    context.fail!(e.message)
  end
end