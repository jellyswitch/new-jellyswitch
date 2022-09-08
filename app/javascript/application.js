// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

import Rails from '@rails/ujs'
import * as ActiveStorage from "@rails/activestorage"
import Turbolinks from "turbolinks"

import "trix"
import "@rails/actiontext"
import "chartkick"
import "Chart.bundle"
import ahoy from "ahoy.js"
window.ahoy = ahoy
import 'bootstrap'

Rails.start()
window.Rails = Rails;
ActiveStorage.start()
Turbolinks.start()

//https://stackoverflow.com/questions/46831525/how-to-keep-submit-buttons-disabled-on-remote-forms-until-the-next-page-has-load/46844912#46844912
// This is to keep rails-ujs from re-enabling the checkout buttons on a turbolinks redirect

;(function () {
  var $doc = $(document)

  $doc.on('ajax:send', 'form[data-remote=true]', function () {
    var $form = $(this)
    var $button = $form.find('[data-disable-with]')
    if (!$button.length) return

    $form.on('ajax:complete', function () {
      // Use setTimeout to prevent race-condition when Rails re-enables the button
      setTimeout(function () {
        $button.each(function () { Rails.disableElement(this) })
      }, 0)
    })

    // Prevent button from being cached in disabled state
    $doc.one('turbolinks:before-cache', function () {
      $button.each(function () { Rails.enableElement(this) })
    })
  })
})()
