Rails.application.routes.draw do
  namespace :api do
    post 'login', to: 'api#login'
    post 'verify', to: 'api#verify'
    post 's3', to: 'api#s3'
    get 's3', to: 'api#s3_get_object'
    resource :user, only: [:show]
    resources :users, only: [:index]

    resources :evaluation_models
    resources :projects do
      resources :records
      member do
        get :model
        get :objects
        get :export
      end
      get :sorted_evaluated, to: 'evaluated#sorted'
      resources :evaluated do
        member do
          post :comprehensive
          get :link
          get :score
        end
        resource :record
        resources :records
      end
    end

    resources :notifications, only: [:index, :create, :destroy]
  end
end
