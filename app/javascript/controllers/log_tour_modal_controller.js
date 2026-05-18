import { Controller } from "@hotwired/stimulus"

// Shared "Log Tour" modal driver — per-row buttons on the People list trigger
// this controller's prepare action with the clicked person's name and the
// log_tour URL as params. We patch the modal title and form action in place
// so the same modal serves every row.
export default class extends Controller {
  static targets = ["form", "title"]

  prepare(event) {
    const name = event.params.name
    const url = event.params.url
    if (this.hasFormTarget && url) {
      this.formTarget.action = url
    }
    if (this.hasTitleTarget && name) {
      this.titleTarget.textContent = name
    }
  }
}
