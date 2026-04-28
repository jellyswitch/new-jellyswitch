class Api::V1::Admin::EmailTemplatesController < Api::V1::Admin::BaseController
  def index
    templates = ProductEmailTemplate.where(operator: current_tenant)

    render json: templates.map { |t|
      {
        id: t.id,
        name: t.product_label,
        subject: t.subject,
        enabled: t.enabled,
        email_type: t.email_type,
        send_count: ProductEmailSend.where(
          operator: current_tenant,
          email_type: t.email_type
        ).where("sent_at > ?", 30.days.ago).count,
      }
    }
  end

  def update
    template = ProductEmailTemplate.find(params[:id])

    if template.update(template_params)
      render json: { id: template.id, subject: template.subject }
    else
      render_error(template.errors.full_messages.join(', '))
    end
  end

  def toggle
    template = ProductEmailTemplate.find(params[:id])
    template.update!(enabled: !template.enabled)

    render json: { id: template.id, enabled: template.enabled }
  end

  def send_log
    template = ProductEmailTemplate.find(params[:id])
    sends = ProductEmailSend.where(
      operator: current_tenant,
      email_type: template.email_type
    ).order(sent_at: :desc).limit(20)

    render json: sends.map { |s|
      {
        id: s.id,
        user_name: s.user&.name,
        sent_at: s.sent_at&.iso8601,
        opened: s.try(:opened) || false,
      }
    }
  end

  private

  def template_params
    params.permit(:subject, :body)
  end
end
