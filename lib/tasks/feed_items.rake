namespace :feed_items do
  desc "Dedupe new-user FeedItems (keep the oldest per user, delete the rest). DRY_RUN=1 to preview."
  task dedupe_new_user: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    deleted = 0
    inspected = 0

    User.find_each do |u|
      new_user_items = FeedItem.where(user_id: u.id)
                                .where("blob->>'type' = ?", "new-user")
                                .order(:created_at)
                                .to_a
      next if new_user_items.size <= 1
      inspected += 1
      keep = new_user_items.first
      drop = new_user_items[1..]
      drop.each do |fi|
        puts "  #{dry_run ? '[would delete]' : '[deleting]'}  fi=#{fi.id} user=#{u.id}/#{u.email} created=#{fi.created_at.iso8601} (keeping fi=#{keep.id})"
        fi.destroy unless dry_run
        deleted += 1
      end
    end

    puts
    puts "Users with duplicate new-user FeedItems: #{inspected}"
    puts "Duplicate FeedItems #{dry_run ? 'would be' : ''} deleted: #{deleted}"
  end
end
