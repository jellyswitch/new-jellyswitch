class Operator::InvoicesController < Operator::BaseController
  before_action :background_image
  def index
    @pagy, @invoices = pagy(Invoice.all.order('date DESC'))
    authorize @invoices
    @title = "All Invoices"
    render :generic
  end

  def recent
    @pagy, @invoices = pagy(Invoice.recent.order('date DESC'))
    authorize @invoices
    @title = "Recent Invoices"
    render :generic
  end

  def delinquent
    @pagy, @invoices = pagy(Invoice.delinquent.order('date DESC'))
    authorize @invoices
    @title = "Delinquent Invoices"
    render :generic
  end

  def groups
    @pagy, @invoices = pagy(Invoice.groups.order('date DESC'))
    authorize @invoices
    @title = "Group Invoices"
    render :generic
  end

  def open
    @pagy, @invoices = pagy(Invoice.open.order('date DESC'))
    authorize @invoices
    @title = "Open Invoices"
    render :generic
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