class AddLoginCodeToUsers < ActiveRecord::Migration[7.2]
  # Passwordless "Login Code" (OTP) login — ADR 0016. Mirrors the reset_digest
  # pattern: store only a digest of the 6-digit code, the time it was sent (for
  # the 10-minute expiry), and a wrong-guess counter (5 burns the code). All
  # additive + nullable; no backfill (a null digest just means "no active code").
  def change
    add_column :users, :login_code_digest, :string
    add_column :users, :login_code_sent_at, :datetime
    add_column :users, :login_code_attempts, :integer, default: 0, null: false
  end
end
