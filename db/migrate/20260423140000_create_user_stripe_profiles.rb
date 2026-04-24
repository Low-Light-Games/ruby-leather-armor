class CreateUserStripeProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :user_stripe_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :plan_key, null: false, default: "free"
      t.string :stripe_customer_id
      t.string :stripe_subscription_id
      t.string :stripe_subscription_status
      t.string :stripe_price_id
      t.datetime :stripe_current_period_end
      t.datetime :delinquent_since
      t.datetime :grace_period_ends_at

      t.timestamps
    end

    add_index :user_stripe_profiles, :stripe_customer_id, unique: true
    add_index :user_stripe_profiles, :stripe_subscription_id, unique: true
    add_index :user_stripe_profiles, :stripe_price_id
  end
end
