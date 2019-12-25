// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, or any plugin's
// vendor/assets/javascripts directory can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// compiled file. JavaScript code in this file should be added after the last require_* statement.
//
// Read Sprockets README (https://github.com/rails/sprockets#sprockets-directives) for details
// about supported directives.
//
//= require rails-ujs
//= require jquery
//= require popper
//= require bootstrap-sprockets
//= require moment
//= require activestorage
//= require turbolinks
//= require Chart.bundle
//= require chartkick
//= require pagy
//= require ahoy
//= require trix
//= require_tree .

// This is required to get Turbolinks 5 to work with non-GET form errors
// see https://github.com/turbolinks/turbolinks/issues/85#issuecomment-219799657
// for more information

document.addEventListener("turbolinks:load", () => {
  document.body.addEventListener("ajax:error", (e) => {
    if (e.detail[2].status !== 422) {
      return
    }
    document.body = e.detail[0].body
    Turbolinks.dispatch("turbolinks:load")
    scrollTo(0, 0)
  })
})

window.addEventListener("turbolinks:load", Pagy.init);
