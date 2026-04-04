class CreateCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :campaigns do |t|
      t.references :operator, null: false
      t.references :location
      t.string :name, null: false
      t.string :campaign_type, null: false, default: "single" # single, drip
      t.jsonb :segment, null: false, default: {}
      t.string :status, null: false, default: "draft" # draft, active, paused, completed, cancelled
      t.integer :recipient_count, default: 0
      t.datetime :scheduled_at
      t.datetime :sent_at
      t.integer :suppression_days, default: 7
      t.timestamps
    end

    create_table :campaign_steps do |t|
      t.references :campaign, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :subject, null: false
      t.text :body, null: false
      t.integer :delay_days, null: false, default: 0
      t.integer :sent_count, default: 0
      t.timestamps
    end

    add_index :campaign_steps, [:campaign_id, :position], unique: true

    create_table :campaign_sends do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :campaign_step, null: false, foreign_key: true
      t.references :user, null: false
      t.string :status, null: false, default: "sent" # sent, failed, skipped
      t.string :error_message
      t.datetime :sent_at
      t.boolean :opened, default: false
      t.datetime :opened_at
      t.boolean :clicked, default: false
      t.datetime :clicked_at
      t.timestamps
    end

    add_index :campaign_sends, [:campaign_step_id, :user_id], unique: true
  end
end
