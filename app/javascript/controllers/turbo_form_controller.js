import {Controller} from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton"];

  connect() {
    this.element.addEventListener('turbo:submit-end', (event) => {
      if (event.detail.success === true) {
        this.submitButtonTarget.disabled = true;
      }
    })
  }
}
