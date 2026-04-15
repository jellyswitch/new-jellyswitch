class Api::V1::InvoicesController < Api::V1::BaseController
  def index
    invoices = Invoice.where(billable: current_api_user, operator: current_tenant)
      .order(created_at: :desc)
      .limit(params[:limit] || 30)
      .offset(params[:offset] || 0)

    render json: invoices.map { |inv| invoice_json(inv) }
  end

  def charge
    invoice = Invoice.find(params[:id])
    return render_error('Not your invoice', status: :forbidden) unless invoice.billable == current_api_user

    result = Billing::ChargeInvoice.call(invoice: invoice) rescue nil

    if result&.success?
      render json: { success: true, message: 'Invoice paid successfully.' }
    else
      render_error(result&.message || 'Unable to charge invoice')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Invoice not found', status: :not_found)
  end

  private

  def invoice_json(inv)
    {
      id: inv.id,
      amount_due: inv.amount_due,
      amount_paid: inv.amount_paid,
      status: inv.status,
      description: inv.try(:description),
      pdf_url: inv.try(:pdf_url),
      due_date: inv.try(:due_date)&.strftime("%B %e, %Y"),
      payment_method: inv.try(:payment_method),
      billable_to: inv.try(:billable)&.try(:name),
      can_charge: inv.status == 'open' && current_api_user.try(:has_billing_for_location?),
      created_at: inv.created_at.strftime("%B %e, %Y"),
    }
  end
end
