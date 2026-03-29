// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

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
import "@nathanvda/cocoon"

ActiveStorage.start();

// Clean up Bootstrap modals before Turbo navigation
(function () {
  $(document).on('turbo:before-visit', function () {
    $('.modal.show').removeClass('show').attr('aria-hidden', 'true').css('display', 'none');
    $('body').removeClass('modal-open').css('padding-right', '');
    $('.modal-backdrop').remove();
  });
})()

