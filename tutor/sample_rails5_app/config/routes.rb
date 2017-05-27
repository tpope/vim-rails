Rails.application.routes.draw do
  get 'comments/index'
  resource :comments, only: [:index, :new]
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
