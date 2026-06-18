class Operator::ConciergeConversationsController < Operator::BaseController
  before_action :require_staff

  def index
    @conversations = ConciergeConversation
                       .where(operator: current_tenant, status: %w[open staffed])
                       .order(updated_at: :desc)
                       .includes(:location, :messages, :user)
  end

  def show
    @conversation = find_conversation
    @messages = @conversation.messages
  end

  def reply
    @conversation = find_conversation
    body = params[:body].to_s
    if body.present?
      @conversation.messages.create!(operator: current_tenant, role: "staff",
                                     author: current_user, body: body)
      @conversation.update!(last_staff_message_at: Time.current, status: "staffed")
    end
    redirect_to concierge_conversation_path(@conversation)
  end

  # JSON poll for the open thread, so staff see new visitor messages live.
  def messages
    convo = find_conversation
    after = params[:after].to_i
    render json: convo.messages.where("id > ?", after).map { |m|
      { id: m.id, role: m.role, body: m.body, author: m.author&.name, at: m.created_at.iso8601 }
    }
  end

  private

  def find_conversation
    ConciergeConversation.where(operator: current_tenant).find(params[:id])
  end

  def require_staff
    return if current_user&.admin? || current_user&.superadmin? ||
              current_user&.general_manager? || current_user&.community_manager?
    redirect_to root_path, alert: "Staff only."
  end
end
