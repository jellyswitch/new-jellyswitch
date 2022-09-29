class ApplicationComponent < ViewComponent::Base
  include ActiveModel::Conversion
  include ActiveModel::Validations
  include ApplicationHelper
end