class BackfillNoteFeedItemPlainText < ActiveRecord::Migration[7.2]
  # The mobile feed now renders note bodies from the rich text at read time, so
  # existing notes already DISPLAY correctly. This also rewrites the stored
  # blob['text'] for existing 'post' feed items from their rich text, so the
  # persisted plain text has decoded entities + line breaks — the old
  # strip_tags value left "&amp;" encoded and ran paragraphs together.
  #
  # Idempotent (skips rows already clean) and uses update_column so it neither
  # bumps updated_at (which would reorder the feed) nor re-fires callbacks.
  disable_ddl_transaction!

  def up
    ActsAsTenant.without_tenant do
      FeedItem.where("blob->>'type' = 'post'").includes(:rich_text_text).find_each do |fi|
        plain = fi.text&.to_plain_text
        next if plain.blank?
        next if fi.blob['text'].to_s == plain

        fi.update_column(:blob, fi.blob.merge("text" => plain))
      end
    end
  end

  def down
    # Lossy cleanup — nothing to restore.
  end
end
