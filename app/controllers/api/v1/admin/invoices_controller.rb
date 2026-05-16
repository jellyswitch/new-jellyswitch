class Api::V1::Admin::InvoicesController < Api::V1::Admin::BaseController
  def index
    invoices = Invoice.where(operator: current_tenant)

    case params[:scope]
    when 'recent'
      invoices = invoices.recent
    when 'delinquent'
      invoices = invoices.delinquent
    when 'open'
      invoices = invoices.open
    when 'paid'
      invoices = invoices.where(status: 'paid')
    end

    invoices = invoices.order(created_at: :desc).limit(params[:limit] || 50)

    render json: invoices.map { |inv|
      begin
        invoice_json(inv)
      rescue => e
        { id: inv.id, amount_due: inv.amount_due, status: inv.status, error: e.message }
      end
    }
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create
    user = User.find(params[:user_id])
    amount = params[:amount]
    description = params[:description]

    result = Billing::Invoices::Custom::Create.call(
      billable: user,
      amount: amount,
      description: description,
      location: current_location,
    )

    if result.success?
      render json: { success: true, invoice_id: result.try(:invoice)&.id }, status: :created
    else
      render_error(result.message)
    end
  end

  def charge
    invoice = Invoice.find(params[:id])

    begin
      result = Billing::Invoices::ChargeInvoice.call(
        invoice: invoice,
        operator: invoice.operator,
      )

      if result.success?
        render json: { success: true }
      else
        render_error(result.message)
      end
    rescue Stripe::InvalidRequestError, Stripe::APIConnectionError, Stripe::StripeError => e
      render_error("Payment processing error: #{e.message}")
    end
  end

  def mark_paid
    invoice = Invoice.find(params[:id])
    invoice.update(status: 'paid')
    render json: { success: true }
  end

  def refund
    invoice = Invoice.find(params[:id])
    refundable = RefundableFactory.for(invoice)

    begin
      result = Billing::Invoices::Refunds::Create.call(
        operator: current_tenant,
        invoice: refundable,
        location: current_location,
      )

      if result.success?
        render json: { success: true, message: 'Refund issued successfully.' }
      else
        render_error(result.message || 'Unable to issue refund')
      end
    rescue Stripe::InvalidRequestError, Stripe::APIConnectionError, Stripe::StripeError => e
      render_error("Refund processing error: #{e.message}")
    end
  end

  def accounting
    location = current_location
    report = Jellyswitch::Report.new(location)

    render json: {
      mrr: report.mrr,
      total_revenue_this_month: location.invoices.this_month.paid.sum(:amount_paid),
      total_revenue_last_month: location.invoices.last_month.paid.sum(:amount_paid),
    }
  rescue => e
    render json: {
      mrr: 0,
      total_revenue_this_month: location.invoices.this_month.paid.sum(:amount_paid),
      total_revenue_last_month: location.invoices.last_month.paid.sum(:amount_paid),
    }
  end

  private

  def invoice_json(inv)
    {
      id: inv.id,
      amount_due: inv.amount_due,
      amount_paid: inv.amount_paid,
      status: inv.status,
      billable_name: inv.billable&.try(:name),
      billable_type: inv.billable_type,
      description: inv.try(:description),
      created_at: inv.created_at,
    }
  end
end
