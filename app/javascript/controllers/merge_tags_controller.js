import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  insert(event) {
    event.preventDefault()

    const tag = event.currentTarget.dataset.tag
    if (!tag) return

    // Find the Trix editor within this controller's scope
    const trixEditor = this.element.querySelector("trix-editor")
    if (!trixEditor || !trixEditor.editor) return

    // Insert the merge tag at the current cursor position
    trixEditor.editor.insertString(tag)
  }
}
