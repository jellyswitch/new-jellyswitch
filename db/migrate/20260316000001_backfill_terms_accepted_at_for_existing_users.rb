class BackfillTermsAcceptedAtForExistingUsers < ActiveRecord::Migration[7.1]
  def up
    # Backfill terms_accepted_at for all existing users who have a phone number
    # (i.e., they signed up normally, not admin-created) but don't yet have
    # terms_accepted_at set. This prevents existing members across all operators
    # from being blocked by the TOS acceptance requirement.
    User.where(terms_accepted_at: nil)
        .where.not(phone: [nil, ""])
        .update_all(terms_accepted_at: Time.current)
  end

  def down
    # No-op: we can't distinguish which users had terms_accepted_at before
  end
end
