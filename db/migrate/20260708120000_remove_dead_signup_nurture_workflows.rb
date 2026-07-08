class RemoveDeadSignupNurtureWorkflows < ActiveRecord::Migration[7.1]
  # The "signup_nurture" AutomatedWorkflow was a non-functional duplicate of the
  # event-driven signup nudge (Users::Save -> ScheduleSignupNudgeJob ->
  # SendProductEmailJob, using the valid signup_nudge/nudge ProductEmailTemplate).
  # Its template lookup used a product_type/email_type the ProductEmailTemplate
  # model forbids, so it never sent while showing a misleading "Signup nurture
  # drip" toggle in the admin. The type is now removed from AutomatedWorkflow::
  # TYPES, so these auto-seeded (disabled) rows are orphaned — delete them.
  def up
    execute("DELETE FROM automated_workflows WHERE workflow_type = 'signup_nurture'")
  end

  def down
    # No-op: the signup_nurture workflow type was dead code. Nothing to restore —
    # the real signup nudge is the event-driven ScheduleSignupNudgeJob path.
  end
end
