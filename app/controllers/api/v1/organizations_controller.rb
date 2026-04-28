class Api::V1::OrganizationsController < Api::V1::BaseController
  def show
    org = current_api_user.organization
    return render json: { organization: nil } unless org

    render json: org_json(org)
  end

  def update
    org = current_api_user.organization
    return render_error('No organization found') unless org
    return render_error('Only the owner can edit this organization') unless org.owner_id == current_api_user.id

    if org.update(org_params)
      render json: org_json(org)
    else
      render_error(org.errors.full_messages.first)
    end
  end

  def add_member
    org = current_api_user.organization
    return render_error('No organization found') unless org
    return render_error('Only the owner can manage members') unless org.owner_id == current_api_user.id

    user = current_tenant.users.find_by(email: params[:email]&.downcase)
    return render_error('User not found') unless user

    user.update(organization: org)
    render json: org_json(org.reload)
  end

  def remove_member
    org = current_api_user.organization
    return render_error('No organization found') unless org
    return render_error('Only the owner can manage members') unless org.owner_id == current_api_user.id

    user = org.users.find(params[:member_id])
    return render_error('Cannot remove yourself') if user.id == current_api_user.id

    user.update(organization: nil)
    render json: org_json(org.reload)
  rescue ActiveRecord::RecordNotFound
    render_error('Member not found')
  end

  def invoices
    org = current_api_user.organization
    return render_error('No organization found') unless org

    invoices = org.invoices.order(created_at: :desc).limit(30)
    render json: invoices.map { |inv|
      {
        id: inv.id,
        amount_due: inv.amount_due,
        status: inv.status,
        description: inv.try(:description),
        pdf_url: inv.try(:pdf_url),
        created_at: inv.created_at.strftime("%B %e, %Y"),
      }
    }
  end

  def payment_method
    org = current_api_user.organization
    return render_error('No organization found') unless org

    if org.stripe_customer_id.present?
      begin
        customer = Stripe::Customer.retrieve(org.stripe_customer_id)
        pm = customer.invoice_settings&.default_payment_method
        if pm.present?
          payment_method = Stripe::PaymentMethod.retrieve(pm)
          card = payment_method.card
          return render json: {
            brand: card.brand,
            last4: card.last4,
            exp_month: card.exp_month,
            exp_year: card.exp_year,
          }
        end
      rescue Stripe::StripeError => e
        Rails.logger.error("Stripe error fetching org payment: #{e.message}")
      end
    end

    render json: { brand: nil, last4: nil }
  end

  private

  def org_params
    params.permit(:name, :website)
  end

  def org_json(org)
    members = org.users.map { |u|
      { id: u.id, name: u.name, email: u.email, role: u.role }
    }

    {
      id: org.id,
      name: org.name,
      website: org.try(:website),
      owner_name: org.owner&.name,
      billing_contact_name: org.billing_contact&.name,
      created_at: org.created_at.strftime("%B %e, %Y"),
      active_subscriptions: org.subscriptions.where(active: true).count,
      invoice_count: org.invoices.count,
      members: members,
      member_count: org.users.count,
      is_owner: org.owner_id == current_api_user.id,
    }
  end
end
