class AddRenewalNoticeSentAtToOfficeLeases < ActiveRecord::Migration[7.1]
  def change
    add_column :office_leases, :renewal_notice_sent_at, :datetime, null: true
  end
end
