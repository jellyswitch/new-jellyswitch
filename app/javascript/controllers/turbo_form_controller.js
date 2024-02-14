import {Controller} from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.addEventListener('turbo:submit-end', (event) => {
      if (event.detail.success === true) {
        this.element.querySelector('button').disabled = true;
      }
    })
  }
}
