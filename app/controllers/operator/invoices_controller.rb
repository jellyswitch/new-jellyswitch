class Operator::InvoicesController < Operator::BaseController
  def index
    @pagy, @invoices = pagy(Invoice.all.order('date DESC'))
    authorize @invoices
    background_image
  end

  def due
    @pagy, @invoices = pagy(Invoice.due.order('date DESC'))
    authorize @invoices
    background_image
  end

  def recent
    @pagy, @invoices = pagy(Invoice.recent.order('date DESC'))
    authorize @invoices
    background_image
  end

  def delinquent
    @pagy, @invoices = pagy(Invoice.delinquent.order('date DESC'))
    authorize @invoices
    background_image
  end
end