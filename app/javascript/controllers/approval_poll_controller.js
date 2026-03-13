import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 5000 } }

  connect() {
    this.poll()
  }

  disconnect() {
    this.stopPolling()
  }

  poll() {
    this.timer = setInterval(() => {
      this.checkApproval()
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
    }
  }

  async checkApproval() {
    try {
      const response = await fetch(this.urlValue)
      const data = await response.json()
      if (data.approved) {
        this.stopPolling()
        window.location.href = "/home"
      }
    } catch (error) {
      // Silently retry on next interval
    }
  }
}
