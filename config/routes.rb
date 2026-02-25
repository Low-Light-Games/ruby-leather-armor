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
    resources :stories, only: [:index, :new, :show, :create, :update, :destroy] do
      resources :story_states, only: [:create, :update, :destroy] do
        member do
          patch :reorder
        end
      end
    end
    resources :dm_logs, only: [:index, :show]
    resources :ai_logs, only: [:index, :show]
    resource :dm_config, only: [:show, :update]
  end

  get "sheets/create" => "stimulus#stimulus_version_sheet_creator"

  # Sheets: HTML (SPA) + JSON API
  resources :sheets

  # API endpoints for stories and adventures
  resources :stories, only: [:index]
  resources :adventures, only: [:index, :new, :create, :show, :destroy] do
    resources :messages, only: [:index, :create], controller: 'adventure_messages'
    post 'messages/roll', to: 'adventure_messages#roll', as: :roll_message
  end
end
