namespace :feed_items do
  desc "Backfill ActionText body for mobile-created management notes. DRY_RUN=1 to preview."
  task backfill_post_action_text: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    fixed = 0
    skipped = 0

    FeedItem.where("blob->>'type' = ?", "post").find_each do |fi|
      if fi.text.present? && fi.text.to_plain_text.present?
        skipped += 1
        next
      end

      body = fi.blob["body"] || fi.blob["text"]
      if body.blank?
        skipped += 1
        next
      end

      puts "  #{dry_run ? '[would fix]' : '[fixing]'}  fi=#{fi.id} op=#{fi.operator_id} created=#{fi.created_at.iso8601}"
      unless dry_run
        fi.text = body
        fi.save!
      end
      fixed += 1
    end

    puts
    puts "Post FeedItems #{dry_run ? 'would be' : ''} backfilled: #{fixed}"
    puts "Skipped (already had ActionText or no body): #{skipped}"
  end

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
