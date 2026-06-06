import { Controller } from "@hotwired/stimulus"

// Polls the import status endpoint while the background job runs, then navigates to
// the result (or back to preview on failure) when it reports done.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.poll()
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  poll() {
    fetch(this.urlValue, { headers: { Accept: "application/json" } })
      .then(response => response.json())
      .then(data => {
        if (data.done && data.redirect) {
          window.location.href = data.redirect
        } else {
          this.timer = setTimeout(() => this.poll(), 3000)
        }
      })
      .catch(() => {
        this.timer = setTimeout(() => this.poll(), 3000)
      })
  }
}
