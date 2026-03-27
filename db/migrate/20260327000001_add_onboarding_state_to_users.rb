class AddOnboardingStateToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :onboarding_state, :string, default: 'new', null: false
    add_index :users, :onboarding_state
  end
end
