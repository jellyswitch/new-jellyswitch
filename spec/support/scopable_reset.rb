RSpec.configure do |config|
  config.before(:each) do
    ActsAsScopable.current_scope_resources = []
  end
end