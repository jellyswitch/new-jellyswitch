class Api::V1::Admin::MembersController < Api::V1::Admin::BaseController
  def index
    users = current_tenant.users
                          .where(approved: true, archived: false)
                          .where.not(role: 'admin')
                          .order(:name)

    users = search_users(users) if params[:q].present?
    users = users.offset(params[:offset].to_i).limit(30)

    render json: users.map { |u| member_list_json(u) }
  end

  def unapproved
    users = current_tenant.users
                          .where(approved: false, archived: false)
                          .where.not(role: 'admin')
                          .order(created_at: :desc)

    users = search_users(users) if params[:q].present?
    users = users.offset(params[:offset].to_i).limit(30)

    render json: users.map { |u| member_list_json(u) }
  end

  def archived
    users = current_tenant.users
                          .where(archived: true)
                          .where.not(role: 'admin')
                          .order(:name)

    users = search_users(users) if params[:q].present?
    users = users.offset(params[:offset].to_i).limit(30)

    render json: users.map { |u| member_list_json(u) }
  end

  def show
    user = current_tenant.users.find(params[:id])
    active_sub = user.subscriptions.find { |s| s.active? && !s.pending? }
    last_checkin = user.checkins.order(datetime_in: :desc).first

    render json: {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      bio: user.bio,
      linkedin: user.try(:linkedin),
      twitter: user.try(:twitter),
      website: user.try(:website),
      role: user.role,
      approved: user.approved,
      plan_name: active_sub&.plan&.name,
      credit_balance: user.credit_balance,
      has_profile_photo: user.has_profile_photo?,
      ltv: Invoice.where(billable: user, operator: current_tenant).sum("GREATEST(amount_paid, amount_due)"),
      last_checkin: last_checkin&.datetime_in,
      member_since: user.created_at,
      payment_method: user.try(:payment_method) || 'None',
      day_pass_count: user.day_passes.where(operator: current_tenant).count,
      reservation_count: user.reservations.where(cancelled: false).count,
      invoice_count: Invoice.where(billable: user, operator: current_tenant).count,
      organization_name: user.try(:organization)&.try(:name),
      day_passes: user.day_passes.where(operator: current_tenant).order(day: :desc).limit(10).map { |dp|
        { id: dp.id, date: dp.day&.strftime("%B %e, %Y"), type_name: dp.day_pass_type&.name }
      },
    }
  end

  def create
    result = Users::Create.call(
      params: user_params.to_h.symbolize_keys,
      operator: current_tenant,
      admin_created: true
    )

    if result.success?
      render json: member_list_json(result.user), status: :created
    else
      render_error(result.error || 'Failed to create user')
    end
  end

  def update
    user = current_tenant.users.find(params[:id])

    if user.update(user_update_params)
      render json: member_list_json(user)
    else
      render_error(user.errors.full_messages.join(', '))
    end
  end

  def approve
    user = current_tenant.users.find(params[:id])
    user.update!(approved: true)

    # Activate pending subscription if one exists
    pending_sub = user.subscriptions.pending.first
    if pending_sub
      pending_sub.update!(pending: false, active: true)
    end

    SendNotificationsJob.perform_later(user)

    render json: { success: true, approved: true }
  end

  def unapprove
    user = current_tenant.users.find(params[:id])
    user.update!(approved: false)

    render json: { success: true, approved: false }
  end

  def archive
    user = current_tenant.users.find(params[:id])
    user.update!(archived: true)

    render json: { success: true, archived: true }
  end

  def unarchive
    user = current_tenant.users.find(params[:id])
    user.update!(archived: false)

    render json: { success: true, archived: false }
  end

  def add_credits
    user = current_tenant.users.find(params[:id])
    amount = params[:amount].to_i
    user.update!(credit_balance: user.credit_balance + amount)

    render json: { success: true, credit_balance: user.credit_balance }
  end

  def change_payment
    user = current_tenant.users.find(params[:id])

    case params[:payment_type]
    when 'card'
      user.update!(out_of_band: false, bill_to_organization: false)
    when 'out_of_band'
      user.update!(out_of_band: true, bill_to_organization: false)
    when 'bill_to_organization'
      user.update!(bill_to_organization: true, out_of_band: false)
    else
      return render_error('Invalid payment type')
    end

    render json: { success: true, payment_method: user.payment_method }
  end

  private

  def search_users(scope)
    q = "%#{params[:q]}%"
    scope.where("users.name ILIKE ? OR users.email ILIKE ?", q, q)
  end

  def member_list_json(user)
    active_sub = user.subscriptions.find { |s| s.active? && !s.pending? }
    {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      role: user.role,
      approved: user.approved,
      plan_name: active_sub&.plan&.name,
      has_profile_photo: user.has_profile_photo?
    }
  end

  def user_params
    params.permit(:name, :email, :phone, :password, :bio, :role)
  end

  def user_update_params
    params.permit(:name, :email, :phone, :bio, :role)
  end
end
