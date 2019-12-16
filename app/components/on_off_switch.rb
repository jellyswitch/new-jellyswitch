class OnOffSwitch < ApplicationComponent
  def initialize(predicate:, path:, disabled: false)
    @predicate = predicate
    @path = path
    @disabled = disabled
  end

  private

  attr_reader :predicate, :path, :disabled
  
  def icon_class
    if predicate
      "fas fa-toggle-on"
    else
      "fas fa-toggle-off"
    end
  end
end