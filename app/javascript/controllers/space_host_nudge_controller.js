import { Controller } from "@hotwired/stimulus"

// Delays a "Have any questions?" bubble on the selection page so it doesn't
// pounce on visitors the moment they land — surfaces after `delayValue` ms,
// remembers dismissal in sessionStorage so it stops nagging in the same
// session, and expands to an inline feedback form on tap.
export default class extends Controller {
  static targets = ["prompt", "form", "comment"]
  static values = {
    delay: { type: Number, default: 10000 },
    storageKey: String,
  }

  connect() {
    if (this.dismissed) return
    this.timer = setTimeout(() => this.reveal(), this.delayValue)
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
  }

  reveal() {
    this.element.hidden = false
    requestAnimationFrame(() => this.element.classList.add("space-host-nudge--visible"))
  }

  expand() {
    this.promptTarget.hidden = true
    this.formTarget.hidden = false
    if (this.hasCommentTarget) {
      this.commentTarget.focus()
    }
  }

  collapse() {
    this.formTarget.hidden = true
    this.promptTarget.hidden = false
  }

  dismiss(event) {
    event?.preventDefault()
    this.element.hidden = true
    this.element.classList.remove("space-host-nudge--visible")
    this.markDismissed()
  }

  // Hook for the form's submit event — lets the form actually submit, but
  // records the dismissal so the bubble doesn't re-pop after the redirect.
  markDismissed() {
    try {
      sessionStorage.setItem(this.storageKeyValue, "1")
    } catch (_e) {
      // Private mode / storage disabled — fine, just won't persist across reloads.
    }
  }

  get dismissed() {
    try {
      return sessionStorage.getItem(this.storageKeyValue) === "1"
    } catch (_e) {
      return false
    }
  }
}
