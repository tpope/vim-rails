class Comment < ApplicationRecord
  belongs_to :user

  def bar_comments
    User.foo_user.comments
  end

end

