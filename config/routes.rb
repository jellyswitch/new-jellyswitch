Rails.application.routes.draw do
  # Root
  root "landing#index"

  # Authentication
  delete '/logout',  to: 'sessions#destroy'
  post '/login',     to: 'sessions#create'
  get '/login',      to: 'sessions#new'
  get '/signup',     to: 'users#new'

  # Landing
  get 'landing/index'
  get '/home',      to: 'landing#home'
  get '/wait',      to: 'landing#wait'
  get '/choose',    to: 'landing#choose'

  # Alphabetized Resources
  resources :day_passes
  resources :doors
  resources :organizations
  resources :plans
  resources :reservations, except: [:index]
  resources :rooms do
    get 'day/:day/:month/:year', to: 'rooms#day', as: :day_availability
  end
  resources :subscriptions
  resources :users do
    get 'change_password', to: 'users#change_password'
    patch 'update_password', to: 'users#update_password'
    patch 'update_organization', to: 'users#update_organization'
    collection do
      get 'add_member', to: 'users#add_member'
    end
  end
end
