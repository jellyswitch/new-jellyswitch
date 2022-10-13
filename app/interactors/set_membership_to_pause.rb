class SetMembershipToPause
  include Interactor

  delegate :subscription, :resumes_at, to: :context

  def call
    if !subscription.update(
      paused: "scheduled", 
      resumes_at: resumes_at
    )
      context.fail!(message: "Subscription couldn't save: #{subscription}")
    end
  end
end