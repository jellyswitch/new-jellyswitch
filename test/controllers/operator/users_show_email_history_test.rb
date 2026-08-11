require "test_helper"

# The admin-only "Email History" card on the profile self-view lists
# ProductEmailSend rows where sendable == the viewed user — the signup-nudge
# and drip/workflow ledger rows. ProductEmailSend has no product_type (that
# column lives on ProductEmailTemplate), so the row label must come from
# email_type, with a product prefix derived from sendable_type only for
# product-sendable rows.
class Operator::UsersShowEmailHistoryTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"
  end

  def create_send!(email_type, status: "sent")
    ProductEmailSend.create!(
      operator: @operator,
      user: @admin,
      sendable: @admin,
      email_type: email_type,
      status: status,
      sent_at: Time.current,
    )
  end

  test "self-view renders a signup-nudge ledger row" do
    create_send!("nudge")

    log_in @admin
    get user_path(@admin), env: default_env

    assert_response :success
    assert_match "Signup Nudge", response.body
  end

  test "self-view renders workflow ledger rows from email_type alone" do
    create_send!(User::WELCOME_DRIP_ENROLLED_KEY, status: "scheduled")

    log_in @admin
    get user_path(@admin), env: default_env

    assert_response :success
    assert_match "Welcome Drip Enrolled", response.body
  end
end
