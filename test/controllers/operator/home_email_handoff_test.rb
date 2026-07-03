require "test_helper"

# Post-purchase email hand-off on the WEB for ALREADY-APPROVED buyers (ADR 0017).
#
# Unapproved buyers land on /wait, whose `shared/_app_download_nudge` partial
# already tells them to "Check your email for how to use the space." But an
# approved repeat buyer (day pass / bundle / membership) is redirected to /home,
# which carries no such partial — so they'd miss the pointer to the
# how-to-use-the-space email.
#
# Fix: append that same line to the post-purchase success flash, but ONLY on the
# approved (home-bound) path. Unapproved buyers go to /wait where the partial
# covers it, so guarding on approved? avoids showing the line twice.
class Operator::HomeEmailHandoffTest < ActionDispatch::IntegrationTest
  # Must match the phrasing in app/views/shared/_app_download_nudge.html.erb so
  # the home flash reads identically to the wait-page nudge.
  EMAIL_LINE = "Check your email for how to use the space."

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user     = users(:cowork_tahoe_member) # approved: true
    host! "#{@operator.subdomain}.example.com"
  end

  test "approved member buying a single day pass gets the email hand-off in the success flash" do
    log_in @user
    DayPassInteractorFactory.stubs(:for).returns(
      stub(call: OpenStruct.new(success?: true, day_pass: OpenStruct.new(today?: true, day: Date.current)))
    )

    post day_passes_path,
      params: { day_pass: { day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type).id } },
      env: default_env

    # Exact match locks the concatenation (single space, base message intact).
    assert_redirected_to home_path
    assert_equal "Welcome to #{@operator.name}! #{EMAIL_LINE}", flash[:success]
  end

  test "approved member buying a day pass bundle gets the email hand-off in the success flash" do
    log_in @user
    bundle_type = day_pass_type(:cowork_tahoe_day_pass_type)
    bundle_type.update!(quantity: 2) # quantity > 1 => N-Pack / bundle SKU
    Billing::DayPassBundles::CreateBundle.stubs(:call).returns(
      OpenStruct.new(success?: true, day_pass_bundle: OpenStruct.new(passes_remaining: 2))
    )

    post day_passes_path,
      params: { day_pass: { day_pass_type: bundle_type.id } },
      env: default_env

    assert_redirected_to home_path
    assert_equal "Thanks! 2 day passes added to your account. #{EMAIL_LINE}", flash[:success]
  end

  test "approved member buying a membership gets the email hand-off in the success flash" do
    log_in @user
    Billing::Subscription::CreateSubscription.stubs(:call).returns(OpenStruct.new(success?: true))
    Billing::Subscription::UpdatePaymentAndCreateSubscription.stubs(:call).returns(OpenStruct.new(success?: true))

    post subscriptions_path,
      params: { subscription: { plan_id: plans(:cowork_tahoe_part_time_plan).id } },
      env: default_env

    assert_redirected_to root_path
    assert_equal "Welcome to #{@location.name}! #{EMAIL_LINE}", flash[:success]
  end

  # Guard: an UNAPPROVED buyer is redirected to /wait, where the partial already
  # carries the line. The flash must NOT also carry it, or the member sees the
  # same sentence twice on one screen.
  test "unapproved day-pass buyer lands on /wait and does NOT get the line in the flash" do
    @user.update!(approved: false)
    log_in @user
    DayPassInteractorFactory.stubs(:for).returns(
      stub(call: OpenStruct.new(success?: true, day_pass: OpenStruct.new(today?: true, day: Date.current)))
    )

    post day_passes_path,
      params: { day_pass: { day_pass_type: day_pass_type(:cowork_tahoe_day_pass_type).id } },
      env: default_env

    # Exactly the base message — the line is NOT appended (the /wait partial
    # already carries it, so appending here would duplicate it).
    assert_redirected_to wait_path
    assert_equal "Welcome to #{@operator.name}!", flash[:success]
  end
end
