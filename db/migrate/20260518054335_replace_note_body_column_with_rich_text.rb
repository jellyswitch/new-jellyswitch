class ReplaceNoteBodyColumnWithRichText < ActiveRecord::Migration[7.1]
  # Notes now use ActionText (has_rich_text :body) so the body lives in
  # action_text_rich_texts keyed by record + name="body". The literal column
  # gets in the way (Rails resolves note.body to the column instead of the
  # association), so drop it.
  #
  # No data backfill: the notes table is empty in prod (the model landed
  # this morning and is not yet wired into any UI). If there were rows,
  # they'd need to be copied into action_text_rich_texts first.
  def up
    remove_column :notes, :body
  end

  def down
    add_column :notes, :body, :text, null: false, default: ""
  end
end
