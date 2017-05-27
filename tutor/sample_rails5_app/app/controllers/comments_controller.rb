class CommentsController < ApplicationController

  def new
    @comment = Comment.new
  end

  def index
    current_user.comments.all
  end

end

