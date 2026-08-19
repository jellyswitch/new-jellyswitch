require "test_helper"

# Tracking pixels are brand-global ad/analytics tags (Google Tag Manager, GA4,
# ad conversion pixels). They must inject on EVERY page of an operator's site —
# including for logged-out visitors on multi-location operators, where no
# current_location resolves. Per-location resolution was the reason a correctly
# configured GTM head snippet never appeared in the header: ad-campaign
# visitors are exactly the logged-out / no-location case.
class Operator::TrackingPixelsRenderTest < ActionDispatch::IntegrationTest
  GTM_HEAD = '<script>window.__gtm_head_probe = 1;</script>'.freeze
  GTM_BODY = '<noscript><iframe src="https://www.googletagmanager.com/ns.html?id=GTM-TEST"></iframe></noscript>'.freeze
  CONV_PIXEL = '<script>window.__conversion_probe = 1;</script>'.freeze

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    # .lvh.me, not .example.com: the test-env session cookie is scoped to
    # domain .lvh.me (config/initializers/sessions.rb), and the purchase-event
    # dance rides the session across requests. On any other host the cookie
    # never round-trips and the dance silently never fires.
    host! "#{@operator.subdomain}.lvh.me"
  end

  test "always-on head pixel renders in <head> for a logged-out visitor on a multi-location operator" do
    # Second location => no current_location resolves for an anonymous visitor
    # (the Untethered case: GTM configured, header injection silently no-oped).
    create(:location, operator: @operator, name: "Second Site")
    create(:tracking_pixel, operator: @operator, location: @location,
           name: "GTM", script: GTM_HEAD, position: :head, always_on: true)

    get "/signup", env: default_env

    assert_response :success
    assert_includes response.body, GTM_HEAD
    assert_operator response.body.index(GTM_HEAD), :<, response.body.index("</head>"),
                    "head pixel must render inside <head>"
  end

  test "always-on body pixel renders unescaped after the opening <body> tag" do
    create(:tracking_pixel, operator: @operator, location: @location,
           name: "GTM noscript", script: GTM_BODY, position: :body, always_on: true)

    get "/signup", env: default_env

    assert_response :success
    # Escaped output (the old <%= pixel.script %>) shows up as &lt;noscript&gt;
    # and can never execute — the snippet must land in the DOM raw.
    assert_includes response.body, GTM_BODY
    body_open = response.body.index(/<body[^>]*>/)
    assert_operator response.body.index(GTM_BODY), :>, body_open
  end

  test "identical snippets saved under several locations inject once" do
    second = create(:location, operator: @operator, name: "Second Site")
    [@location, second].each do |loc|
      create(:tracking_pixel, operator: @operator, location: loc,
             name: "GTM", script: GTM_HEAD, position: :head, always_on: true)
    end

    get "/signup", env: default_env

    assert_response :success
    assert_equal 1, response.body.scan(GTM_HEAD).size
  end

  test "purchase pushes a one-shot dataLayer purchase event and fires conversion-only pixels" do
    create(:tracking_pixel, operator: @operator, location: @location,
           name: "Ad conversion", script: CONV_PIXEL, position: :body, always_on: false)
    user = users(:cowork_tahoe_member) # approved: true
    log_in user
    dpt = day_pass_type(:cowork_tahoe_day_pass_type)
    DayPassInteractorFactory.stubs(:for).returns(
      stub(call: OpenStruct.new(success?: true,
                                day_pass: OpenStruct.new(today?: true, day: Date.current,
                                                         id: 4242, day_pass_type: dpt)))
    )

    post day_passes_path, params: { day_pass: { day_pass_type: dpt.id } }, env: default_env
    assert_redirected_to home_path

    first  = render_page(home_path) # arming render (turbo_redirect effectively renders twice)
    second = render_page(home_path) # the render the buyer actually sees — fires here
    third  = render_page(home_path) # one-shot: gone again

    assert_no_match(/"event":"purchase"/, first)
    refute_includes first, CONV_PIXEL

    assert_match(/"event":"purchase"/, second)
    assert_match(/"product_type":"day_pass"/, second)
    assert_match(/"product_name":"#{Regexp.escape(dpt.name)}"/, second)
    assert_match(/"value":#{Regexp.escape((dpt.amount_in_cents / 100.0).to_s)}/, second)
    assert_match(/"transaction_id":"dp_4242"/, second)
    assert_includes second, CONV_PIXEL

    assert_no_match(/"event":"purchase"/, third)
    refute_includes third, CONV_PIXEL
  end

  private

  # Follow any intermediate redirects to the page a member actually sees; the
  # layout (and so set_tracking_pixels) only runs on 200 renders.
  def render_page(path)
    get path, env: default_env
    follow_redirect! while response.redirect?
    assert_response :success
    response.body
  end
end
