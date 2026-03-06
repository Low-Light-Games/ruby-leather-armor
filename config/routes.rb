Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public legal / OGL page (no authentication required)
  get "legal" => "legal#index"

  # Root redirects based on role: admin → DM Logs, user → Sheets
  root "home#index"

  # Authentication routes
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"
  get "current_user" => "sessions#show"

  # Admin routes
  get "admin/all_sheets" => "admin#all_sheets"

  namespace :admin do
    resources :adventures, only: [:index, :show, :update] do
      member do
        patch :reset_context
        patch :update_sheet
        patch :update_story_element
      end
    end
    resources :stories, only: [:index, :new, :show, :create, :update, :destroy] do
      member { post :enrich }
    end
    resources :dm_logs, only: [:index, :show]
    resources :ai_logs, only: [:index, :show] do
      collection do
        get :pipelines
        get "pipelines/:pipeline_run_id", action: :pipeline, as: :pipeline
      end
    end
    resources :feature_flags, only: [:index] do
      member { patch :toggle }
    end
    resource :dm_config, only: [:show, :update] do
      get :models, on: :member
    end
    resource :billing, only: [:show], controller: "billing"
  end

  resources :feature_flags, only: [:index]

  get "sheets/create" => "stimulus#stimulus_version_sheet_creator"

  # Read-only game-rule definition endpoints
  resources :feat_definitions,  only: [:index, :show]
  resources :spell_definitions, only: [:index, :show]
  resources :item_definitions,  only: [:index, :show]

  # Sheets: HTML (SPA) + JSON API
  resources :sheets

  # API endpoints for stories and adventures
  resources :stories, only: [:index]
  resources :adventures, only: [:index, :new, :create, :show, :destroy] do
    resources :messages, only: [:index, :create], controller: 'adventure_messages'
    post 'messages/roll', to: 'adventure_messages#roll', as: :roll_message
    post 'messages/initiative', to: 'adventure_messages#initiative', as: :initiative_message
    resource :adventure_sheet, only: [:update] do
      patch :toggle_equip
    end
  end
end
