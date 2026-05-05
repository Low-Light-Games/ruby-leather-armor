Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public pages (no authentication required)
  get "legal"   => "legal#index"
  get "privacy" => "privacy#index"

  root "home#index"

  # Authentication routes
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"
  get "current_user" => "sessions#show"

  # OmniAuth callbacks
  get  "auth/:provider/callback", to: "omniauth_callbacks#google_oauth2", as: :omniauth_callback
  get  "auth/failure",            to: "omniauth_callbacks#failure"
  post "auth/:provider/callback", to: "omniauth_callbacks#google_oauth2"

  # First-login wizard (API — UI is embedded in AdventureCreation)
  post "onboarding/complete", to: "onboarding#complete", as: :onboarding_complete
  get "plans", to: "subscriptions#plans", as: :plans
  get "subscription/success", to: "subscriptions#success", as: :subscription_success
  post "subscription/checkout", to: "subscriptions#checkout", as: :subscription_checkout
  post "subscription/portal", to: "subscriptions#portal", as: :subscription_portal
  post "webhooks/stripe", to: "stripe_webhooks#create", as: :stripe_webhooks

  namespace :admin do
    resources :adventures, only: [:index, :show, :update, :destroy] do
      member do
        patch :update_combat_context
        patch :reset_combat_context
        patch :update_sheet
        patch :update_story_element
      end
    end
    resources :stories, only: [:index, :new, :show, :create, :update, :destroy]
    resources :play_logs, only: [:index, :show] do
      collection do
        get :pipelines
        get "pipelines/:registry_entry_uuid", action: :pipeline, as: :pipeline
        get "pipelines/:registry_entry_uuid/export", action: :export_pipeline, as: :export_pipeline
      end
    end
    resources :feature_flags, only: [:index, :edit, :update]
    resource :dm_config, only: [:show, :update] do
      get :models, on: :member
    end
    resource :billing, only: [:show], controller: "billing"
    resources :users, only: [:index, :show] do
      member do
        patch :update_plan
        patch :ban
        patch :unban
        patch :trust
        patch :untrust
      end
    end
    resources :bestiary_entries, only: [:index] do
      collection do
        get :import_candidates
        post :import
      end
    end
  end

  resources :feature_flags, only: [:index]

  # Read-only game-rule definition endpoints
  resources :feat_definitions,  only: [:index, :show]
  resources :spell_definitions, only: [:index, :show]
  resources :item_definitions,  only: [:index, :show]

  # Sheets: HTML (SPA) + JSON API
  resources :sheets do
    collection do
      get :adventure_options
    end
  end

  # API endpoints for stories and adventures
  resources :stories, only: [:index]
  resources :adventures, only: [:index, :new, :create, :show, :destroy] do
    resources :messages, only: [:index, :create], controller: 'adventure_messages'
    post 'messages/roll', to: 'adventure_messages#roll', as: :roll_message
    post 'messages/initiative', to: 'adventure_messages#initiative', as: :initiative_message
    resource :adventure_sheet, only: [:update] do
      patch :toggle_equip
    end
    resource :combat_action, only: [:create], controller: 'combat_actions' do
      get :options, on: :collection
    end
  end

  resource :user_preferences, only: [:update]
end
