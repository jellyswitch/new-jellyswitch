class Api::V1::InvoicesController < Api::V1::BaseController
  def index
    invoices = Invoice.where(billable: current_api_user, operator: current_tenant)
      .order(created_at: :desc)
      .limit(params[:limit] || 30)
      .offset(params[:offset] || 0)

    render json: invoices.map { |inv|
      {
        id: inv.id,
        amount_due: inv.amount_due,
        amount_paid: inv.amount_paid,
        status: inv.status,
        description: inv.try(:description),
        pdf_url: inv.try(:pdf_url),
        created_at: inv.created_at.strftime("%B %e, %Y"),
      }
    }
  end
end
