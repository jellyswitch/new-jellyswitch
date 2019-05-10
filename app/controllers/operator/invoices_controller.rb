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

  def charge
    find_invoice(:invoice_id)
    authorize @invoice

    result = Billing::Invoices::ChargeInvoice.call(
      invoice: @invoice,
      operator: @invoice.operator
    )

    if result.success?
      flash[:success] = "Charge succeeded."
    else
      flash[:error] = result.message
    end

    turbolinks_redirect(referrer_or_root, action: "replace")
  end

  private

  def find_invoice(key=:id)
    @invoice = Invoice.find(params[key])
  end
end