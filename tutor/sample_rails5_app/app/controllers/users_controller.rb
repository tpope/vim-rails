class UsersController < ApplicationController
  layout :users

  def index
    User.all
  end

end

