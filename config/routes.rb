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

  # Alphabetized Resources
  resources :organizations

  resources :reservations

  resources :rooms
  
  resources :users do
    get 'change_password', to: 'users#change_password'
    patch 'update_password', to: 'users#update_password'

    patch 'update_organization', to: 'users#update_organization'
  end
end
