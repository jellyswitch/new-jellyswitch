class BackfillCardAddedOnMembers < ActiveRecord::Migration[5.2]
  def change
    users = User.all

    reversible do |dir|
      dir.up do
        users.each do |user|
          if user.stripe_customer && user.stripe_customer.sources["data"].count > 0
            user.update(card_added: true)
          end
        end
      end

      dir.down do
        users.update_all(card_added: false)
      end
    end
  end
end
