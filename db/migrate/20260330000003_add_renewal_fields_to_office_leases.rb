class AddRenewalFieldsToOfficeLeases < ActiveRecord::Migration[7.1]
  def change
    add_column :office_leases, :auto_renew, :boolean, null: false, default: false
    add_column :office_leases, :renewal_notice_days, :integer, null: false, default: 60
    add_column :office_leases, :escalation_type, :string
    add_column :office_leases, :escalation_value, :decimal, precision: 10, scale: 2
    add_column :office_leases, :cpi_index_series_id, :string
  end
end
