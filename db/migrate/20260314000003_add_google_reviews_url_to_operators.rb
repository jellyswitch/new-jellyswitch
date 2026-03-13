class AddGoogleReviewsUrlToOperators < ActiveRecord::Migration[7.1]
  def change
    add_column :operators, :google_reviews_url, :string
  end
end
