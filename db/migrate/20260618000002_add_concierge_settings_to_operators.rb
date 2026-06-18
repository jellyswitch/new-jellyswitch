class AddConciergeSettingsToOperators < ActiveRecord::Migration[7.2]
  def change
    # Lean per-brand Concierge config — all nullable, sensible defaults applied
    # in the model so a brand works on day one with zero config.
    add_column :operators, :concierge_assistant_name, :string
    add_column :operators, :concierge_greeting, :string
    add_column :operators, :concierge_offer_text, :string
    add_column :operators, :concierge_promo_code, :string
    add_column :operators, :concierge_off_hours_message, :string

    # Shared embed-theme (used by BOTH the Concierge and the tour widget).
    add_column :operators, :embed_font, :string
    add_column :operators, :embed_accent_override, :string
  end
end
