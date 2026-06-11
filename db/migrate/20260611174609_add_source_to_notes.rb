class AddSourceToNotes < ActiveRecord::Migration[7.1]
  def change
    add_reference :notes, :source, polymorphic: true, null: true, index: true
  end
end
