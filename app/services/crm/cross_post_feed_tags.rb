module Crm
  # Mirrors a team-Feed post/comment onto the records of any CUSTOMERS tagged in
  # it (a "Customer Tag"). Staff mentions are handled separately (a push, in the
  # feed controller). A tagged member gets a Note on their own record and NO
  # push — it's an internal note ABOUT them, never a message TO them. The Note
  # carries the full text, the tagger as author, and a `source` link back to the
  # Feed item. Snapshot: not synced to later edits/deletes. See ADR 0006.
  class CrossPostFeedTags
    def self.call(text:, source:, author:)
      return if text.blank? || !text.include?("@")

      operator = author.operator
      operator.users.mentionable.find_each do |user|
        next if user.name.blank?
        next if user.id == author.id
        next if User::STAFF_ROLES.include?(user.role) # staff → push elsewhere, not cross-post
        next unless text.match?(/@#{Regexp.escape(user.name)}(?![[:alnum:]])/)

        note = Note.new(notable: user, author: author, operator: operator, source: source)
        note.body = text
        note.save!
      end
    rescue => e
      Honeybadger.notify(e)
      Rails.logger.error("Crm::CrossPostFeedTags error: #{e.class}: #{e.message}")
    end
  end
end
