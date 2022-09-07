ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "minitest/unit"
require "mocha/minitest"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)
  
  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  parallelize_setup do |worker|
    Searchkick.index_suffix = worker

    # reindex models
    # [Announcement, Room, Door, Location, Organization, FeedItem, User].map {|klass| klass.reindex }

    # and disable callbacks
    Searchkick.disable_callbacks
  end
end

class ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def default_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'Something safari something else' }
  end

  def ios_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'something Jellyswitch something else deviceToken: abcdef12345' }
  end

  def log_in(user)
    user.update(password: 'password')
    ActsAsTenant.default_tenant = user.operator
    post login_path( params: { session: { email: user.email, password: 'password' } } )
  end
end

# reindex models
# [Announcement, Room, Door, Location, Organization, FeedItem, User].map {|klass| klass.reindex }

# and disable callbacks
Searchkick.disable_callbacks
