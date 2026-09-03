module Embed
  # Lets an operator admin preview a script-embed widget from the settings
  # page even while it is disabled. Same idea as the Tour / Concierge preview
  # tokens: the settings view signs a short-lived, operator-scoped token into
  # the widget URL, so the preview doesn't depend on session cookies crossing
  # the embed boundary and can't preview another operator's widget.
  module AdminPreview
    extend ActiveSupport::Concern

    class_methods do
      def preview_verifier
        Rails.application.message_verifier("#{controller_name}_preview")
      end

      def preview_token_for(operator)
        preview_verifier.generate({ "operator_id" => operator.id, "exp" => 1.hour.from_now.to_i })
      end
    end

    private

    def admin_previewing?
      token = params[:preview_token]
      return false if token.blank?

      payload = self.class.preview_verifier.verify(token).with_indifferent_access
      payload[:operator_id] == @operator.id && payload[:exp].to_i > Time.current.to_i
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      false
    end
  end
end
