source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.4.4'

gem "aws-sdk-s3", require: false
gem 'bcrypt'
gem 'faker', :git => 'https://github.com/stympy/faker.git', :branch => 'master'
gem 'friendly_id'
gem 'icalendar'
gem 'image_processing', '~> 1.2'
gem 'jbuilder', '~> 2.5'
gem 'jquery-rails'
gem 'octicons_helper'
gem 'pg'
gem 'puma', '~> 3.11'
gem 'pundit'
gem 'rails', '~> 5.2.0'
gem 'sass-rails', '~> 5.0'
gem 'turbolinks', '~> 5'
gem 'uglifier', '>= 1.3.0'

group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'better_errors'
  gem 'binding_of_caller'
  gem 'user-auth', git: "https://github.com/dpaola2/user-auth"
end

group :test do
  gem 'capybara', '>= 2.15', '< 4.0'
  gem 'selenium-webdriver'
  gem 'chromedriver-helper'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
end
