import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "roomName", "roomDetails", "endTime", "durationLabel",
    "slider", "priceBox", "priceAmount", "includedRemaining",
    "confirmBtn", "billingSection"
  ]
  static values = {
    roomId: Number,
    duration: Number,
    maxDuration: Number,
    startTime: String,
    date: String,
    dayOrNight: String,
    priceUrl: String,
    createUrl: String,
  }

  connect() {
    this.startTime = new Date(this.startTimeValue)
    this.currentRoomId = this.roomIdValue
    this.currentDuration = this.durationValue
  }

  onDurationChange(event) {
    this.currentDuration = parseInt(event.target.value)
    this.updateEndTime()
    this.updateDurationLabel()
    this.fetchPrice()
  }

  updateEndTime() {
    const end = new Date(this.startTime.getTime() + this.currentDuration * 60000)
    const hours = end.getHours()
    const minutes = end.getMinutes()
    const ampm = hours >= 12 ? "PM" : "AM"
    const displayHour = hours > 12 ? hours - 12 : hours === 0 ? 12 : hours
    const displayMin = minutes.toString().padStart(2, "0")
    this.endTimeTarget.textContent = `${displayHour}:${displayMin} ${ampm}`
  }

  updateDurationLabel() {
    const min = this.currentDuration
    if (min < 60) {
      this.durationLabelTarget.textContent = `${min} min`
    } else if (min % 60 === 0) {
      const hrs = min / 60
      this.durationLabelTarget.textContent = `${hrs} hr${hrs > 1 ? "s" : ""}`
    } else {
      this.durationLabelTarget.textContent = `${(min / 60).toFixed(1)} hrs`
    }
  }

  async fetchPrice() {
    const params = new URLSearchParams({
      room_id: this.currentRoomId,
      duration: this.currentDuration,
      date: this.dateValue,
    })

    try {
      const response = await fetch(`${this.priceUrlValue}?${params}`)
      const data = await response.json()

      // ADR 0019 included-room coverage: remember the state for the Confirm
      // Booking prompt, and surface the day-pass cost the plain room price hides.
      this._coverage = data.coverage
      this._coverageFlag = null
      const cov = data.coverage
      const coverageActive = cov && ["needs_purchase", "bundle_available", "reusable_pass"].includes(cov.state)

      if (coverageActive) {
        this.renderCoverageBox(cov)
      } else if (data.included) {
        this.priceBoxTarget.className = "mx-3 p-3 rounded border border-success"
        this.priceBoxTarget.style.background = "#e8f5e0"
        let remainingText = ""
        if (data.included_minutes_remaining) {
          const rem = data.included_minutes_remaining
          remainingText = rem >= 60 ? `${Math.floor(rem / 60)} hrs remaining` : `${rem} min remaining`
        }
        this.priceBoxTarget.innerHTML = `
          <div class="d-flex justify-content-between align-items-center">
            <span class="text-success">Included in your plan</span>
            <strong class="text-success">${remainingText}</strong>
          </div>
        `
      } else {
        this.priceBoxTarget.className = "mx-3 p-3 rounded"
        this.priceBoxTarget.style.background = "#f8f9fa"
        const price = parseFloat(data.total_price).toFixed(2)
        this.priceBoxTarget.innerHTML = `
          <div class="d-flex justify-content-between align-items-center">
            <span class="text-muted">Total</span>
            <strong class="text-success" style="font-size: 24px;">$${price}</strong>
          </div>
        `
      }

      // Show/hide Stripe billing section: pay when the room is charged OR the
      // member is buying a day pass to cover an included room (needs_purchase).
      const needsPay = data.should_charge || (coverageActive && cov.state === "needs_purchase")
      if (this.hasBillingSectionTarget) {
        this.billingSectionTarget.style.display = needsPay ? "block" : "none"
      }
    } catch (e) {
      console.error("Error fetching price:", e)
    }
  }

  selectRoom(event) {
    const card = event.currentTarget
    this.currentRoomId = parseInt(card.dataset.roomId)
    const name = card.dataset.roomName
    const capacity = card.dataset.roomCapacity
    const amenities = card.dataset.roomAmenities
    const rate = parseInt(card.dataset.roomRate)

    // Update hero card
    this.roomNameTarget.textContent = name
    this.roomDetailsTarget.textContent = `${capacity} people · ${amenities}`

    // Update slider max based on new room availability
    // For now keep max duration — in production this would AJAX fetch
    this.fetchPrice()
  }

  async confirmBooking() {
    // Guard against double-invocation: a mobile touch can fire this handler
    // twice before button.disabled propagates, causing duplicate POSTs that
    // race each other and surface as a "time slot conflicts" error on the
    // second one even though the first succeeded.
    if (this._booking) return

    // ADR 0019: an included room commits a day pass for its date — confirm the
    // reuse/burn/buy decision before booking (parity with the mobile Alert).
    const cc = this._coverageConfirm()
    if (cc && !this._coverageFlag) {
      if (!window.confirm(cc.body)) return
      this._coverageFlag = cc.flag
    }

    this._booking = true

    const btn = this.confirmBtnTarget
    btn.disabled = true
    btn.textContent = "Booking..."

    const startTime = this.startTime
    const hours = startTime.getHours()
    const displayHour = hours > 12 ? hours - 12 : hours === 0 ? 12 : hours
    const minutes = startTime.getMinutes().toString().padStart(2, "0")
    const timeStr = `${displayHour}:${minutes}`

    const formData = new FormData()
    formData.append("room_id", this.currentRoomId)
    formData.append("date", this.dateValue)
    formData.append("time", timeStr)
    formData.append("duration", this.currentDuration)
    formData.append("day_or_night", this.dayOrNightValue)

    // ADR 0019: the member's coverage decision (use_existing_pass / use_bundle_pass / buy_day_pass).
    if (this._coverageFlag) formData.append(this._coverageFlag, "true")

    // Add Stripe token if present
    if (window.has_token && document.querySelector('input[name="stripeToken"]')) {
      formData.append("stripeToken", document.querySelector('input[name="stripeToken"]').value)
    }

    // Add CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      formData.append("authenticity_token", csrfToken)
    }

    try {
      const response = await fetch(this.createUrlValue, {
        method: "POST",
        body: formData,
        headers: {
          "Accept": "text/vnd.turbo-stream.html, text/html",
          "X-CSRF-Token": csrfToken,
        },
      })

      if (response.redirected) {
        window.location.href = response.url
      } else {
        const html = await response.text()
        // Handle turbo stream response
        if (response.ok) {
          document.body.insertAdjacentHTML("beforeend", html)
        } else {
          btn.disabled = false
          btn.textContent = "Confirm Booking"
          this._booking = false
        }
      }
    } catch (e) {
      console.error("Booking error:", e)
      btn.disabled = false
      btn.textContent = "Confirm Booking"
      this._booking = false
    }
  }

  // ADR 0019: render the included-room coverage state in the price box.
  renderCoverageBox(cov) {
    const over = Number(cov.overage_in_cents || 0)
    const overLine = over > 0
      ? `<div class="small text-muted mt-1">+ $${(over / 100).toFixed(2)} meeting-room overage</div>`
      : ""
    let label, right
    if (cov.state === "needs_purchase") {
      label = "Day pass required"
      right = `$${(Number(cov.day_pass_amount_in_cents || 0) / 100).toFixed(2)}`
    } else if (cov.state === "bundle_available") {
      label = "Uses 1 of your day passes"
      right = `${cov.bundle_passes_remaining} left`
    } else { // reusable_pass
      label = "Uses your existing day pass"
      right = ""
    }
    this.priceBoxTarget.className = "mx-3 p-3 rounded border border-success"
    this.priceBoxTarget.style.background = "#e8f5e0"
    this.priceBoxTarget.innerHTML = `
      <div class="d-flex justify-content-between align-items-center">
        <span class="text-success">${label}</span>
        <strong class="text-success">${right}</strong>
      </div>${overLine}
    `
  }

  // Mirrors src/utils/coverageConfirm.js (mobile). Returns {flag, body} when the
  // member must confirm a coverage decision before booking, else null.
  _coverageConfirm() {
    const cov = this._coverage
    if (!cov) return null
    const day = this._prettyDate(this.dateValue)
    const over = Number(cov.overage_in_cents || 0)
    const overLine = over > 0 ? ` Plus a $${(over / 100).toFixed(2)} meeting-room overage.` : ""
    switch (cov.state) {
      case "reusable_pass":
        return {
          flag: "use_existing_pass",
          body: `Use your existing day pass${cov.reusable_from_date ? ` (from ${this._prettyDate(cov.reusable_from_date)})` : ""} for ${day}?${overLine}`,
        }
      case "bundle_available":
        return {
          flag: "use_bundle_pass",
          body: `This booking uses 1 of your ${cov.bundle_passes_remaining} day passes for ${day}.${overLine}`,
        }
      case "needs_purchase":
        return {
          flag: "buy_day_pass",
          body: `This room needs a day pass for ${day} — $${(Number(cov.day_pass_amount_in_cents || 0) / 100).toFixed(2)}.${overLine}`,
        }
      default:
        return null
    }
  }

  _prettyDate(iso) {
    if (!iso) return "that day"
    const d = new Date(`${iso}T12:00:00`)
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric" })
  }
}
