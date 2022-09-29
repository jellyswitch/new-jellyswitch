# typed: strong
# == Schema Information
#
# Table name: location_resources
#
#  id :integer          not null, primary key
#

class LocationResource < ApplicationRecord
  belongs_to :location
  belongs_to :resource, polymorphic: true
end
