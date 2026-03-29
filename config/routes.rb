Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  # Public pages — always at root, no auth required
  get "legal"   => "legal#index"
  get "privacy" => "privacy#index"

  root "home#index"

  # OmniAuth — stays at root /auth so it works from both localhost:3000/app
  # and app.leatherarmor.io (nginx bypasses /auth/ without the /app/ rewrite).
  get  "auth/:provider/callback", to: "omniauth_callbacks#google_oauth2", as: :omniauth_callback
  get  "auth/failure",            to: "omniauth_callbacks#failure"
  post "auth/:provider/callback", to: "omniauth_callbacks#google_oauth2"

  # Admin — separate namespace, unaffected by /app scope
  namespace :admin do
    resources :adventures, only: [:index, :show, :update, :destroy] do
      member do
        patch :reset_context
        patch :update_sheet
        patch :update_story_element
      end
    end
    resources :stories, only: [:index, :new, :show, :create, :update, :destroy] do
      member { post :enrich }
    end
    resources :play_logs, only: [:index, :show] do
      collection do
        get :pipelines
        get "pipelines/:pipeline_run_id", action: :pipeline, as: :pipeline
        get "pipelines/:pipeline_run_id/export", action: :export_pipeline, as: :export_pipeline
      end
    end
    resources :feature_flags, only: [:index] do
      member { patch :toggle }
    end
    resource :dm_config, only: [:show, :update] do
      get :models, on: :member
    end
    resource :billing, only: [:show], controller: "billing"
    resources :bestiary_entries, only: [:index] do
      collection do
        get :import_candidates
        post :import
      end
    end
  end

  # ── Player application (/app) ──────────────────────────────────────────────
  # All player-facing routes are scoped under /app.
  # Locally: localhost:3000/app/...
  # Production: app.leatherarmor.io/... (proxy rewrites to /app before Rails sees it)
  # This means routing is identical in both environments — no env vars needed.
  scope "/app" do
    get  "",                    to: "home#app",           as: :app

    # Auth — under /app so the SPA at app.leatherarmor.io can reach them
    # without crossing back to the main domain.
    post   "login"        => "sessions#create",    as: :login
    delete "logout"       => "sessions#destroy",   as: :logout
    get    "current_user" => "sessions#show",      as: :current_user

    post "onboarding/complete", to: "onboarding#complete", as: :onboarding_complete

    resources :feature_flags, only: [:index]

    resources :feat_definitions,  only: [:index, :show]
    resources :spell_definitions, only: [:index, :show]
    resources :item_definitions,  only: [:index, :show]

    resources :sheets

    resources :stories, only: [:index]
    resources :adventures, only: [:index, :new, :create, :show, :destroy] do
      resources :messages, only: [:index, :create], controller: "adventure_messages"
      post "messages/roll",       to: "adventure_messages#roll",       as: :roll_message
      post "messages/initiative", to: "adventure_messages#initiative", as: :initiative_message
      resource :adventure_sheet, only: [:update] do
        patch :toggle_equip
      end
    end
  end
end
