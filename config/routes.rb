Rails.application.routes.draw do
  constraints subdomain: 'www' do
    # Root
    root "landing#index"

    # Authentication
    delete '/logout',  to: 'sessions#destroy'
    post '/login',     to: 'sessions#create'
    get '/login',      to: 'sessions#new'
    get '/signup',     to: 'users#new'
  end

  # Operator root
  root "operator/landing#index"

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
  resources :users do
    post 'approve', to: "users#approve"
    post 'unapprove', to: "users#unapprove"
    get 'change_password', to: 'users#change_password'
    patch 'update_password', to: 'users#update_password'
    patch 'update_organization', to: 'users#update_organization'
    get :memberships, to: 'users#memberships'
    get :day_passes, to: 'users#day_passes'
    get :reservations, to: 'users#reservations'
    get :invoices, to: 'users#invoices'
    get :billing, to: 'users#edit_billing'
    post :billing, to: 'users#update_billing'
    collection do
      get 'add_member', to: 'users#add_member'
      get 'unapproved', to: 'users#unapproved'
    end
  end
end
