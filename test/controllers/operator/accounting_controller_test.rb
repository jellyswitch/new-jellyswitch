require "test_helper"

# /accounting/expenses summed a nonexistent feed_items.amount COLUMN —
# PG::UndefinedColumn 500 for every operator (expense amounts live in
# blob['amount'] as integer cents, written by FeedItem#parse_amount). Hit
# live by Tahoe Longhouse staff 2026-07-28. These pin the jsonb sum and its
# junk-tolerance.
class Operator::AccountingControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"
  end

  def make_item(amount, expense: true)
    blob = { "type" => "post", "text" => "Supplies run" }
    blob["amount"] = amount unless amount.nil?
    FeedItem.create!(
      operator: @operator,
      location: @location,
      user: @admin,
      expense: expense,
      blob: blob,
    )
  end

  test "expenses page renders and totals blob amounts (cents)" do
    make_item(1000)
    make_item(2550)
    make_item(99_999, expense: false) # a plain note — must not count

    log_in @admin
    get expenses_accounting_index_path, env: default_env

    assert_response :success
    assert_match "$35.50", response.body
  end

  test "missing or non-numeric blob amounts count as zero instead of 500ing" do
    make_item(nil)     # expense flagged but no parsed amount
    make_item("$12")   # junk string an old writer could have left
    make_item(500)

    log_in @admin
    get expenses_accounting_index_path, env: default_env

    assert_response :success
    assert_match "$5.00", response.body
  end
end
