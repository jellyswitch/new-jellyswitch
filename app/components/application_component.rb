class ApplicationComponent < ViewComponent::Base
  include ActiveModel::Validations

  # Requires that a content block be passed to the component
  validates :content, presence: true

  def before_render
    validate!
  end
end