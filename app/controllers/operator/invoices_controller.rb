class Operator::InvoicesController < Operator::BaseController
  def index
    @invoices = Invoice.all.order('date DESC')
    authorize @invoices
    background_image
  end

  def due
    @invoices = Invoice.due.order('date DESC')
    authorize @invoices
    background_image
  end

  def recent
    @invoices = Invoice.recent.order('date DESC')
    authorize @invoices
    background_image
  end

  def delinquent
    @invoices = Invoice.delinquent.order('date DESC')
    authorize @invoices
    background_image
  end
end