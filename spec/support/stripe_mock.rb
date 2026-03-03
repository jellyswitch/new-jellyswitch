Rails.configuration.stripe[:test_secret_key] ||= "sk_test_fake_key"
Rails.configuration.stripe[:secret_key] ||= "sk_test_fake_key"
Rails.configuration.stripe[:test_publishable_key] ||= "pk_test_fake_key"
Rails.configuration.stripe[:publishable_key] ||= "pk_test_fake_key"

RSpec.configure do |config|
  config.before(:each, type: :system) do
    StripeMock.start
  end

  config.after(:each, type: :system) do
    StripeMock.stop
  end
end
