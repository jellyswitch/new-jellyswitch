Rails.application.routes.draw do
  get 'landing/index'
  resources :users do
    get 'change_password', to: 'users#change_password'
    patch 'update_password', to: 'users#update_password'
  end
  delete '/logout',  to: 'sessions#destroy'
  post '/login',     to: 'sessions#create'
  get '/login',      to: 'sessions#new'
  get '/signup',     to: 'users#new'
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  root "landing#index"
end
