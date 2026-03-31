import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  connect() {
    this.poll()
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  poll() {
    fetch(this.urlValue)
      .then(response => response.json())
      .then(data => {
        if (data.approved) {
          window.location.reload()
        } else {
          this.timer = setTimeout(() => this.poll(), 10000)
        }
      })
      .catch(() => {
        this.timer = setTimeout(() => this.poll(), 10000)
      })
  }
}
