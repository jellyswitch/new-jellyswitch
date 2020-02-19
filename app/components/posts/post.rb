class Posts::Post < ApplicationComponent
  include ApplicationHelper

  def initialize(post:)
    @post = post
  end

  private

  attr_accessor :post
end