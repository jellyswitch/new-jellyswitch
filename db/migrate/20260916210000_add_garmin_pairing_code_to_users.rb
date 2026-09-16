# Garmin watch pairing codes live on the user like login codes do
# (login_code_digest) rather than in Rails.cache: the phone mints the code and
# the watch redeems it in a separate request that may land on another dyno,
# and the production cache store is per-process. SHA-256 (not bcrypt) so the
# watch can look the code up directly; the code is 6 digits, lives 10 minutes,
# is single-use and rate-limited at the edge (Rack::Attack).
class AddGarminPairingCodeToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :garmin_pairing_code_digest, :string
    add_column :users, :garmin_pairing_code_expires_at, :datetime
    # Unique so two members can never hold the same live code; partial so the
    # NULL majority costs nothing.
    add_index :users, :garmin_pairing_code_digest, unique: true,
              where: "garmin_pairing_code_digest IS NOT NULL",
              name: "index_users_on_garmin_pairing_code_digest"
  end
end
