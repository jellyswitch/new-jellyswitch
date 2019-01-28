Rails.application.routes.draw do
  constraints subdomain: 'app' do
    # Root
    root "landing#index"

    # Authentication
    delete '/logout',  to: 'sessions#destroy', as: :operator_logout
    post '/login',     to: 'sessions#create', as: :operator_login_create
    get '/login',      to: 'sessions#new', as: :operator_login
    get '/signup',     to: 'users#new', as: :operator_signup
  end

  # Operator root
  root "operator/landing#index"

  # Operator Authentication
  delete '/logout',  to: 'operator/sessions#destroy'
  post '/login',     to: 'operator/sessions#create'
  get '/login',      to: 'operator/sessions#new'
  get '/signup',     to: 'operator/users#new'

  # Landing
  get 'landing/index', to: 'operator/landing#index'
  get '/home',      to: 'operator/landing#home'
  get '/wait',      to: 'operator/landing#wait'
  get '/choose',    to: 'operator/landing#choose'

  # Alphabetized Resources
  resources :day_passes, controller: 'operator/day_passes'
  resources :doors, controller: 'operator/doors' do
    get 'open', to: 'doors#open'
    collection do
      get 'keys', to: 'doors#keys'
    end
  end
  resources :organizations, controller: 'operator/organizations'
  resources :plans, controller: 'operator/plans' do
    post 'unarchive', to: 'plans#unarchive'
  end
  resources :reservations, controller: 'operator/reservations', except: [:index]
  resources :rooms, controller: 'operator/rooms', except: [:destroy] do
    get 'day/:day/:month/:year', to: 'rooms#day', as: :day_availability
  end
  resources :subscriptions, controller: 'operator/subscriptions'
  resources :users, controller: 'operator/users' do
    post 'approve', to: "operator/users#approve"
    post 'unapprove', to: "operator/users#unapprove"
    get 'change_password', to: 'operator/users#change_password'
    patch 'update_password', to: 'operator/users#update_password'
    patch 'update_organization', to: 'operator/users#update_organization'
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
