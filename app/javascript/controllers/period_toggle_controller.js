import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { current: { type: String, default: "12m" } }

  select(event) {
    event.preventDefault()
    const period = event.currentTarget.dataset.period

    // Update active button
    this.buttonTargets.forEach(btn => {
      btn.classList.remove("btn-primary")
      btn.classList.add("btn-outline-secondary")
    })
    event.currentTarget.classList.remove("btn-outline-secondary")
    event.currentTarget.classList.add("btn-primary")

    // Reload page with period param
    const url = new URL(window.location)
    url.searchParams.set("period", period)
    Turbo.visit(url.toString(), { action: "replace" })
  }
}
