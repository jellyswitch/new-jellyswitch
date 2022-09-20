ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "policy_assertions"
require "mocha/minitest"
require_relative './clearance_helper'

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

  def setup_initial_user_fixtures
    @admin = UserContext.new(users(:cowork_tahoe_admin), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @member = UserContext.new(users(:cowork_tahoe_member), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @community_manager = UserContext.new(users(:cowork_tahoe_community_manager), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @general_manager = UserContext.new(users(:cowork_tahoe_general_manager), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @superadmin = UserContext.new(users(:cowork_tahoe_superadmin), operators(:cowork_tahoe), locations(:cowork_tahoe))
  end
end

class ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ClearanceHelper

  def default_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'Something safari something else' }
  end

  def ios_env
    @default_env ||= { 'HTTP_USER_AGENT' => 'something Jellyswitch something else deviceToken: abcdef12345' }
  end
end

# reindex models
# [Announcement, Room, Door, Location, Organization, FeedItem, User].map {|klass| klass.reindex }

# and disable callbacks
Searchkick.disable_callbacks
