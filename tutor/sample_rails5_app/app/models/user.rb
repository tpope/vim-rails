class User < ApplicationRecord
  has_many :comments

  def self.foo_user
    first
  end

end

