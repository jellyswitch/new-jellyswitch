class Operator::InstantBookController < Operator::BaseController
  def index
    room = current_location&.rooms&.visible&.first
    render html: "INSTANT BOOK - Room: #{room&.name || 'NIL'} | Location: #{current_location&.name || 'NIL'} | User: #{current_user&.id || 'NIL'}".html_safe, layout: false
  end
end
