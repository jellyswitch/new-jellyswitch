class AddLastPurchasedAtToInterestTags < ActiveRecord::Migration[7.1]
  # When a Person's interest in a product came from an actual purchase, record
  # WHEN they last bought it. Lets us mark the most-recent purchase across their
  # per-product interest tags without destroying sibling tags. Null = the tag was
  # never a purchase signal (concierge / staff / looked_at).
  def change
    add_column :interest_tags, :last_purchased_at, :datetime
  end
end
