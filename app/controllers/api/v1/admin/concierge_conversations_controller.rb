module Api
  module V1
    module Admin
      # Staff-facing Concierge inbox (mobile + web). List live conversations,
      # read a thread, and reply — the human half of the hybrid persona.
      class ConciergeConversationsController < Api::V1::Admin::BaseController
        def index
          convos = ConciergeConversation
                     .where(operator: current_tenant, status: %w[open staffed])
                     .order(updated_at: :desc)
                     .includes(:location, :messages)
          render json: convos.map { |c| summary(c) }
        end

        def show
          convo = find_conversation
          return head(:not_found) unless convo
          render json: summary(convo).merge(messages: convo.messages.map { |m| message_json(m) })
        end

        def reply
          convo = find_conversation
          return head(:not_found) unless convo

          body = params[:body].to_s
          return render(json: { error: "empty" }, status: :unprocessable_entity) if body.blank?

          message = convo.messages.create!(
            operator: current_tenant, role: "staff", author: current_api_user, body: body
          )
          convo.update!(last_staff_message_at: Time.current, status: "staffed")

          render json: { ok: true, message: message_json(message) }
        end

        private

        def find_conversation
          ConciergeConversation.where(operator: current_tenant).find_by(id: params[:id])
        end

        def summary(convo)
          last = convo.messages.max_by(&:created_at)
          {
            id: convo.id,
            status: convo.status,
            location: convo.location&.name,
            person_name: convo.user&.name,
            awaiting_staff: convo.awaiting_staff_timeout?,
            last_message: last&.body,
            updated_at: convo.updated_at.iso8601,
          }
        end

        def message_json(message)
          {
            id: message.id, role: message.role, body: message.body,
            author: message.author&.name, at: message.created_at.iso8601,
          }
        end
      end
    end
  end
end
