class Demo::CreateSubdomains
  include Interactor

  def call
    25.times do |i|
      Subdomain.create(subdomain: "demo#{i}")
    end
  end
end