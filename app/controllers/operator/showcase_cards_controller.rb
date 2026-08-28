class Operator::ShowcaseCardsController < Operator::BaseController
  before_action :require_admin!

  def create
    card = ShowcaseCard.new(card_params)
    card.operator = current_tenant
    # The location must be the operator's own — a forged location_id must not
    # attach a card to another tenant's widget.
    card.location = current_tenant.locations.find_by(id: params.dig(:showcase_card, :location_id))
    if card.location && card.save
      redirect_to settings_website_widgets_path, notice: "Card added."
    else
      redirect_to settings_website_widgets_path, alert: card.errors.full_messages.to_sentence.presence || "Pick a location."
    end
  end

  def destroy
    card = ShowcaseCard.where(operator: current_tenant).find(params[:id])
    card.destroy
    redirect_to settings_website_widgets_path, notice: "Card removed."
  end

  private

  def require_admin!
    redirect_to root_path, alert: "Admins only." unless admin? || superadmin?
  end

  def card_params
    params.require(:showcase_card).permit(:label, :description, :price_text, :url, :slot, :display_order, :visible)
  end
end
