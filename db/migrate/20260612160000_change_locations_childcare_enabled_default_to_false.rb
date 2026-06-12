class ChangeLocationsChildcareEnabledDefaultToFalse < ActiveRecord::Migration[7.1]
  # Childcare gating reads location.childcare_enabled. The column defaulted to
  # true while every other gated module (and the operator-level flag) defaults
  # to false, so brand-new operators surfaced childcare on their plans without
  # opting in. Align the default; existing rows are untouched.
  def change
    change_column_default :locations, :childcare_enabled, from: true, to: false
  end
end
