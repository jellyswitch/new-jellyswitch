class FixOutofbandAndCardaddedUsers < ActiveRecord::Migration[7.0]
  def change
    User.where(out_of_band: true, card_added: true).update_all(out_of_band: false)
  end
end
