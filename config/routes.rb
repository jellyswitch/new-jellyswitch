Rails.application.routes.draw do
  constraints subdomain: 'app' do
    # Root
    root "landing#index"

    # Authentication
    delete '/logout',  to: 'sessions#destroy', as: :operator_logout
    post '/login',     to: 'sessions#create', as: :operator_login_create
    get '/login',      to: 'sessions#new', as: :operator_login
    get '/signup',     to: 'users#new', as: :operator_signup

    resources :operators do
      collection do
        get :demo_instance, to: 'operators#demo_instance'
      end
    end
    resources :operator_surveys do
      collection do
        get :wait, to: 'operator_surveys#wait'
      end
    end
    resources :webhooks do
      collection do
        post :stripe, to: 'webhooks#stripe'
      end
    end
    resources :users
  end

  # Privacy Policy

  get '/privacy-policy', to: 'operator/landing#privacy_policy'

  # Operator root
  root "operator/landing#index"

  # Operator Authentication
  delete '/logout',  to: 'operator/sessions#destroy'
  post '/login',     to: 'operator/sessions#create'
  get '/login',      to: 'operator/sessions#new'
  get '/signup',     to: 'operator/users#new'

  # Landing
  get 'landing/index', to: 'operator/landing#index', as: :landing
  get '/home',      to: 'operator/landing#home'
  get '/wait',      to: 'operator/landing#wait'
  get '/choose',    to: 'operator/landing#choose'

  # Other
  get '/members_resources', to: "operator/landing#members_resources", as: :members_resources

  # Alphabetized Resources
  resources :accounting, controller: 'operator/accounting' do
    collection do
      get 'expenses', to: 'operator/accounting#expenses', as: :expenses
    end
  end
  resources :day_passes, controller: 'operator/day_passes'
  resources :day_pass_types, controller: 'operator/day_pass_types'
  resources :doors, controller: 'operator/doors' do
    get 'open', to: 'operator/doors#open'
    collection do
      get 'keys', to: 'operator/doors#keys'
    end
  end
  resources :feed_items, controller: 'operator/feed_items' do
    resources :comments, controller: 'operator/feed_item_comments', only: [:create]
  end
  resources :invoices, only: [:index], controller: 'operator/invoices' do
    collection do
      get :due, to: 'operator/invoices#due'
      get :recent, to: 'operator/invoices#recent'
      get :delinquent, to: 'operator/invoices#delinquent'
    end
  end
  resources :member_feedbacks, controller: 'operator/member_feedbacks'
  resources :organizations, controller: 'operator/organizations'
  resources :operators, as: :operator_operators, controller: 'operator/operators' do
    get :stripe_connect_setup, to: 'operator/operators/stripe_connect_setup'
  end
  resources :password_resets, only: [:new, :create, :edit, :update], controller: 'operator/password_resets'
  resources :plans, controller: 'operator/plans' do
    post 'unarchive', to: 'operator/plans#unarchive'
  end
  resources :reservations, controller: 'operator/reservations', except: [:index]
  resources :rooms, controller: 'operator/rooms', except: [:destroy] do
    get 'day/:day/:month/:year', to: 'operator/rooms#day', as: :day_availability
  end
  resources :subscriptions, controller: 'operator/subscriptions'
  resources :users, controller: 'operator/users' do
    post 'approve', to: "operator/users#approve"
    post 'unapprove', to: "operator/users#unapprove"
    get 'change_password', to: 'operator/users#change_password'
    patch 'update_password', to: 'operator/users#update_password'
    patch 'update_organization', to: 'operator/users#update_organization'
    patch 'update_payment_method', to: 'operator/users#update_payment_method'
    get 'mark_invoice_as_paid', to: 'operator/users#mark_invoice_as_paid'
    get :memberships, to: 'operator/users#memberships'
    get :day_passes, to: 'operator/users#day_passes'
    get :reservations, to: 'operator/users#reservations'
    get :invoices, to: 'operator/users#invoices'
    get :billing, to: 'operator/users#edit_billing'
    post :billing, to: 'operator/users#update_billing'
    collection do
      get 'add_member', to: 'operator/users#add_member'
      get 'unapproved', to: 'operator/users#unapproved'
    end
  end
end
