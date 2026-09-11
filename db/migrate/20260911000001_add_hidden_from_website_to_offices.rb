class AddHiddenFromWebsiteToOffices < ActiveRecord::Migration[7.2]
  # `visible` on offices means active-vs-archived (it drives the office list,
  # lease availability, renewals). Staff need a way to keep an office active
  # but off the website's Office Inventory widget (e.g. an office held back
  # for internal use) — that's this flag. Default false: nothing hides today.
  def change
    add_column :offices, :hidden_from_website, :boolean, default: false, null: false
  end
end
