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

      if (data.included) {
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

      // Show/hide Stripe billing section
      if (data.should_charge && this.hasBillingSectionTarget) {
        this.billingSectionTarget.style.display = "block"
      } else if (this.hasBillingSectionTarget) {
        this.billingSectionTarget.style.display = "none"
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
        }
      }
    } catch (e) {
      console.error("Booking error:", e)
      btn.disabled = false
      btn.textContent = "Confirm Booking"
    }
  }
}
