class AddPauseWarningToLocations < ActiveRecord::Migration[7.2]
  # Free-text house rule shown to a member before they pause a membership
  # (mobile + web). Blank means no warning — a space that has nothing to say
  # about pausing shouldn't invent a storage policy for itself.
  def change
    add_column :locations, :pause_warning, :text
  end
end
