source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.4'

gem 'activejob-traffic_control'
gem 'acts_as_tenant', '0.5.0'
gem 'ahoy_matey'
gem 'aws-sdk-s3', '~> 1.48', require: false
gem 'bcrypt'
gem 'bootstrap', '~> 4.3.1'
gem 'chartkick', '>= 3.4.0'
gem 'dotenv-rails', require: 'dotenv/rails-now'
gem 'draper'
gem 'faker', :git => 'https://github.com/stympy/faker.git', :branch => 'master'
gem 'fcm'
gem 'friendly_id'
gem 'groupdate'
gem 'honeybadger'
gem 'houston'
gem 'httparty'
gem 'icalendar'
gem 'image_processing', '>= 1.12.2'
gem 'interactor', "~> 3.0"
gem 'jbuilder', '~> 2.5'
gem 'jquery-rails', '>= 4.4.0'
gem 'json', '>= 2.3.0'
gem 'mail_hatch' #, path: "/Users/dave/projects/jellyswitch/mail_hatch"
gem 'momentjs-rails', '>= 2.9.0'
gem 'money'
gem 'newrelic_rpm'
gem 'octicons_helper'
gem 'opensearch-ruby'
gem 'pagy', '~> 4.10.1'
gem 'pg'
gem 'premailer-rails'
gem 'puma', '~> 5.0'
gem 'pundit'
gem 'rails', '~> 6.1.6', '>= 6.1.6.1'
gem 'rails_autolink'
gem 'redis'
gem 'remotipart', '~> 1.2'
gem 'request_store'
gem 'roadie-rails', '~> 2.0'
gem 'sassc-rails', '~> 2.1'
gem 'searchkick'
gem 'sidekiq', '~> 5.2.10'
gem 'simple_calendar'
gem 'stripe', '~> 5.0.0'
gem 'turbolinks', '5.2.1'
gem 'uglifier', '>= 1.3.0'
gem 'view_component'
gem 'webpacker', '~> 5.x'
gem 'working_hours'

group :development do
  gem 'annotate'
  gem 'better_errors', '>= 2.8.0'
  gem 'binding_of_caller'
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'rack-mini-profiler', '~> 2.0'
  gem 'rails-erd'
  gem 'user-auth', git: "https://github.com/jellyswitch/user-auth", :branch => 'master'
  gem 'web-console', '>= 4.1.0'
end

group :test do
  gem 'capybara', '>= 3.2.6'
  gem 'ffi'
  gem 'policy-assertions'
  gem 'selenium-webdriver'
  gem 'webdrivers', '~> 3.0'
end

group :development, :test do
  gem 'bundler-audit'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'factory_bot_rails', '~> 5.0.1'
  gem 'pry-byebug'
  gem 'pry-rails'
  gem 'rails-controller-testing'
  gem 'rspec-rails', '~> 3.8'
  gem 'rspec_junit_formatter'
end
