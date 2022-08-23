/* eslint no-console:0 */
// This file is automatically compiled by Webpack, along with any other files
// present in this directory. You're encouraged to place your actual application logic in
// a relevant structure within app/javascript and only use these pack files to reference
// that code so it'll be compiled.
//
// To reference this file, add <%= javascript_pack_tag 'application' %> to the appropriate
// layout file, like app/views/layouts/application.html.erb


// Uncomment to copy all static images under ../images to the output folder and reference
// them with the image_pack_tag helper in views (e.g <%= image_pack_tag 'rails.png' %>)
// or the `imagePath` JavaScript helper below.
//
// const images = require.context('../images', true)
// const imagePath = (name) => images(name, true)

import Rails from '@rails/ujs'
import * as ActiveStorage from "@rails/activestorage"
import Turbolinks from "turbolinks"
// import "channels"
import "trix"
import "@rails/actiontext"
import "chartkick/chart.js"
import ahoy from "ahoy.js"
window.ahoy = ahoy
import 'bootstrap'
import './pagy.js.erb'

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


// require("trix")
// require("@rails/actiontext")