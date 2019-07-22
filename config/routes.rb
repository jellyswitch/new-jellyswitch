# typed: strict
Rails.application.routes.draw do
  constraints subdomain: "apply" do
    # Typeform
    get :welcome, to: "landing#welcome"
  end
  constraints subdomain: "app" do
    # Root
    root "landing#index"

    # Typeform
    get :welcome, to: "landing#welcome"

    # Authentication
    delete "/logout", to: "sessions#destroy", as: :operator_logout
    post "/login", to: "sessions#create", as: :operator_login_create
    get "/login", to: "sessions#new", as: :operator_login
    get "/signup", to: "onboarding#new_user", as: :operator_signup

    get :stripe_connect_setup, to: "landing#stripe_connect_setup", as: :stripe_connect_setup

    resources :onboarding do
      collection do
        get :new_user
        post :create_user
        get :new_user_info
        post :create_user_info
        get :new_location
        post :create_location
        get :new_member_info
        post :create_member_info
        get :new_images
        post :create_images
      end
    end
    resources :operators
    resources :operator_surveys do
      collection do
        get :wait, to: "operator_surveys#wait"
      end
    end
    resources :webhooks do
      collection do
        post :stripe, to: "webhooks#stripe"
      end
    end
    resources :users
  end

  # Privacy Policy

  get "/privacy-policy", to: "operator/landing#privacy_policy"

  # Operator root
  root "operator/landing#index"

  # Operator Authentication
  delete "/logout", to: "operator/sessions#destroy"
  get "/logout", to: "sessions#destroy"
  post "/login", to: "operator/sessions#create"
  get "/login", to: "operator/sessions#new"
  get "/signup", to: "operator/users#new"

  # Landing
  get "landing/index", to: "operator/landing#index", as: :landing
  get "/home", to: "operator/landing#home"
  get "/wait", to: "operator/landing#wait"
  get "/choose", to: "operator/landing#choose"
  get "/activate", to: "operator/landing#activate"
  post "/activate_membership", to: "operator/landing#activate_membership"
  get "/upgrade", to: "operator/landing#upgrade"

  # Other
  get "/members_resources", to: "operator/landing#members_resources", as: :members_resources # TODO delete this
  get "/members_groups", to: "operator/landing#members_groups", as: :members_groups
  get "/offices_leases", to: "operator/landing#offices_leases", as: :offices_leases
  get "/plans_day_passes", to: "operator/landing#plans_day_passes", as: :plans_day_passes
  get "/customization", to: "operator/landing#customization", as: :customization

  # Admin namespace (for operator resources)
  namespace :operator do
    namespace :admin do
      resources :subscriptions
      resources :day_passes
    end
  end

  # Alphabetized Member Resources
  resources :accounting, controller: "operator/accounting" do
    collection do
      get "expenses", to: "operator/accounting#expenses", as: :expenses
      get "update_expenses", to: "operator/accounting#update_expenses"
    end
  end
  resources :checkins, controller: "operator/checkins" do
    collection do
      get :required, to: "operator/checkins#required"
    end
  end
  resources :day_passes, controller: "operator/day_passes" do
    collection do
      get :code, to: "operator/day_passes#code"
      post :code, to: "operator/day_passes#redeem_code"
      get :redeem_paid, to: "operator/day_passes#redeem_paid"
    end
  end
  resources :day_pass_types, controller: "operator/day_pass_types"
  resources :doors, controller: "operator/doors" do
    get "open", to: "operator/doors#open"
    collection do
      get "keys", to: "operator/doors#keys"
    end
  end
  resources :feed_items, controller: "operator/feed_items" do
    collection do
      get :questions
      get :activity
      get :notes
      get :expenses
    end
    member do
      post "set_expense_status"
      post "unset_expense_status"
    end
    resources :comments, controller: "operator/feed_item_comments", only: [:create]
  end
  resources :invoices, only: [:index], controller: "operator/invoices" do
    resources :refunds, only: [:create], controller: "operator/refunds"
    get :mark_paid, to: "operator/mark_invoices_paid#update"
    collection do
      get :groups, to: "operator/invoices#groups"
      get :open, to: "operator/invoices#open"
      get :recent, to: "operator/invoices#recent"
      get :delinquent, to: "operator/invoices#delinquent"
    end
    get :charge
  end
  resources :locations, controller: "operator/locations"
  resources :member_feedbacks, controller: "operator/member_feedbacks"
  resources :onboarding, controller: "operator/onboarding", as: :operator_onboarding do
    collection do
      get :new_membership_plan
      post :create_membership_plan
      get :new_day_pass_type
      post :create_day_pass_type
      get :new_room
      post :create_room
      get :add_members
      get :new_member
      post :create_member
    end
  end
  resources :offices, controller: "operator/offices"
  resources :office_leases, controller: "operator/office_leases"
  resources :organizations, controller: "operator/organizations" do
    post :billing, to: "operator/organization_billing#create"
    post :add_member, to: "operator/organization_members#create"
  end
  resources :operators, as: :operator_operators, controller: "operator/operators" do
    get :stripe_connect_setup, to: "operator/operators/stripe_connect_setup"
  end
  resources :password_resets, only: [:new, :create, :edit, :update], controller: "operator/password_resets"
  resources :plans, controller: "operator/plans" do
    post "unarchive", to: "operator/plans#unarchive"
  end
  resources :reports, controller: "operator/reports" do
    collection do
      get :member_csv
      get :active_members
      get :active_lease_members
      get :active_leases
      get :last_30_day_passes
      get :total_members
      get :membership_breakdown
      get :revenue
      get :monetization
      get :checkins
    end
  end
  resources :reservations, controller: "operator/reservations", except: [:index, :new, :create] do
    collection do
      get :choose_day, to: "operator/reservations#choose_day"
      get :choose_time, to: "operator/reservations#choose_time"
      post :choose_time_post, to: "operator/reservations#choose_time_post"
      get :choose_duration, to: "operator/reservations#choose_duration"
      get :confirm, to: "operator/reservations#confirm"
      get :create_reservation, to: "operator/reservations#create_reservation"
      post :update_billing_and_create_reservation, to: "operator/reservations#update_billing_and_create_reservation"
    end
  end
  resources :rooms, controller: "operator/rooms", except: [:destroy] do
    get "day/:day/:month/:year", to: "operator/rooms#day", as: :day_availability
  end
  resources :search_results, only: [:new, :create], controller: "operator/search_results" do
    collection do
      get :query, to: "operator/search_results#query"
    end
  end
  resource :set_location, only: [:edit, :update], controller: "operator/set_location"
  resources :subscriptions, controller: "operator/subscriptions"
  resources :users, controller: "operator/users" do
    get :approve, to: "operator/users#approve"
    get :unapprove, to: "operator/users#unapprove"
    get "change_password", to: "operator/users#change_password"
    patch "update_password", to: "operator/users#update_password"
    patch "update_organization", to: "operator/users#update_organization"
    patch "update_payment_method", to: "operator/users#update_payment_method"
    get :memberships, to: "operator/users#memberships"
    get :day_passes, to: "operator/users#day_passes"
    get :reservations, to: "operator/users#reservations"
    get :invoices, to: "operator/users#invoices"
    get :billing, to: "operator/users#edit_billing"
    post :billing, to: "operator/users#update_billing"
    collection do
      get "add_member", to: "operator/users#add_member"
      get "unapproved", to: "operator/users#unapproved"
    end
    get :out_of_band, to: "operator/users#out_of_band"
    get :credit_card, to: "operator/users#credit_card"
    get :bill_to_organization, to: "operator/users#bill_to_organization"
  end
  resources :weekly_updates, controller: "operator/weekly_updates"
end
