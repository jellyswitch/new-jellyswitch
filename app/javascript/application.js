// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

import Rails from '@rails/ujs'
import * as ActiveStorage from "@rails/activestorage"

import "trix"
import "@rails/actiontext"
import "@hotwired/turbo-rails"
import "chartkick"
import "Chart.bundle"
import ahoy from "ahoy.js"
window.ahoy = ahoy
import 'bootstrap'
import "controllers"

Rails.start()
window.Rails = Rails;
ActiveStorage.start()
