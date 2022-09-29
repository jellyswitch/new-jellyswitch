 strong
class ApplicationRecord < ActiveRecord::Base
  include ActsAsScopable::ModelExtensions

  self.abstract_class = true
end
