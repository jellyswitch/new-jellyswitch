import { Controller } from "@hotwired/stimulus"

// Operator Day Pass Type form (Task 13, ADR 0026). A Day Office's capacity
// comes from its room pool, not daily_limit, so daily_limit hides and the
// pool shows only when kind is day_office. The meeting-room allowance field
// stays visible for both kinds, but seeds to 0 the moment an admin switches
// TO Day Office — 0 is the decided billing (overage bills from minute one),
// not just a placeholder.
export default class extends Controller {
  static targets = ["kind", "dailyLimit", "pool", "allowance"]

  connect() {
    this.toggleSections()
  }

  kindChanged() {
    if (this.isDayOffice && this.hasAllowanceTarget && this.allowanceTarget.value.trim() === "") {
      this.allowanceTarget.value = 0
    }
    this.toggleSections()
  }

  toggleSections() {
    // `hidden` only hides dailyLimit visually — the input isn't disabled, so
    // it still submits whatever value is stored there on every save. That's
    // deliberate, not a leak: DayPassType#daily_limit_reached? already
    // ignores daily_limit for day_office (the room pool IS the capacity), so
    // the stale value sits inert and simply resurfaces, correctly, if the
    // type is ever switched back to standard.
    if (this.hasDailyLimitTarget) this.dailyLimitTarget.hidden = this.isDayOffice
    if (this.hasPoolTarget) this.poolTarget.hidden = !this.isDayOffice
  }

  get isDayOffice() {
    return this.kindTarget.value === "day_office"
  }
}
