# Audit: `onboarded?` callers — impact of adding `stripe_user_id` requirement

Date: 2026-05-17
Branch: claude/onboarding-wizard
Purpose: Determine whether expanding `Operator#onboarded?` to also require
`stripe_user_id.present?` is safe to ship without breaking active operators.

## Raw grep output

```
app/helpers/landing_helper.rb:        if current_tenant.onboarded? || current_tenant.skip_onboarding?
spec/models/location_spec.rb:    describe '#onboarded?' do
spec/models/location_spec.rb:        expect(location.onboarded?).to be true
spec/models/location_spec.rb:        expect(location.onboarded?).to be false
spec/models/operator_spec.rb:    describe '#onboarded?' do
spec/models/operator_spec.rb:        expect(operator.onboarded?).to be true
app/models/operator.rb:  def onboarded?
app/models/location.rb:  def onboarded?
app/controllers/operator/feed_items_controller.rb:    if !current_tenant.onboarded? && !current_tenant.skip_onboarding?
app/controllers/landing_controller.rb:          if location.onboarded?
app/controllers/landing_controller.rb:          if current_user.operator.onboarded?
app/views/operator/feed_items/_sidebar.html.erb:<% if !current_location.onboarded? %>
```

Total callers (excluding definition sites and test assertions): **8 unique call sites**

## Analysis

### 1. `app/models/operator.rb:201` — definition site

`Operator#onboarded?` currently checks: plans present, day_pass_types present,
members present. The proposed expansion adds `stripe_user_id.present?`.
This is the method under change — not a caller.

### 2. `app/models/location.rb:192` — definition site

`Location#onboarded?` is a parallel check scoped to a single location (plans,
day_pass_types, members). It does **not** currently check `stripe_user_id`
either. `Location` already has a separate `stripe_setup?` predicate
(`stripe_user_id.present?`). The two call sites inside `landing_controller.rb`
use `location.onboarded?`, not `operator.onboarded?` — see entries #5 and #6
below. The expansion plan targets `Operator#onboarded?` only; `Location#onboarded?`
is out of scope and is not affected.

### 3. `app/helpers/landing_helper.rb:5` — SAFE

```ruby
if current_tenant.onboarded? || current_tenant.skip_onboarding?
```

Called from `landing_redirect` to decide whether to send an admin/manager to
the operator dashboard (`feed_items_path`) or to the onboarding wizard. The
`|| current_tenant.skip_onboarding?` short-circuit means any operator with
`skip_onboarding: true` (i.e., grandfathered / manually bypassed operators)
will continue landing on the dashboard regardless of the new Stripe check.

**After expansion:** Operators without Stripe who also lack `skip_onboarding`
will be redirected to the wizard. This is the desired behavior — the wizard
will prompt them to connect Stripe.

**Verdict: DESIRED behavior change.**

### 4. `app/controllers/operator/feed_items_controller.rb:17` — SAFE

```ruby
if !current_tenant.onboarded? && !current_tenant.skip_onboarding?
  turbo_redirect(new_operator_onboarding_path, action: "replace")
```

The `&& !current_tenant.skip_onboarding?` guard means operators with
`skip_onboarding: true` are never redirected to the wizard, no matter what
`onboarded?` returns.

**After expansion:** Same as above — operators without Stripe + without the
skip flag get bounced to the wizard from the feed index. Intended.

**Verdict: DESIRED behavior change.**

### 5. `app/controllers/landing_controller.rb:42` — LOW-RISK, scoped to error path

```ruby
if location.onboarded?
  redirect_to modules_url(...)
else
  redirect_to landing_url(...)
```

This call uses **`location.onboarded?`** (not `operator.onboarded?`) and lives
inside the Stripe Connect error branch of `stripe_connect_setup`. It only fires
when `Operators::FinishStripeConnect.call` returns a failure — i.e., a broken
OAuth callback. Since the expansion targets `Operator#onboarded?`, not
`Location#onboarded?`, this site is **not affected**.

**Verdict: NOT AFFECTED (different receiver).**

### 6. `app/controllers/landing_controller.rb:48` — LOW-RISK, scoped to error path

```ruby
if current_user.operator.onboarded?
  redirect_to modules_url(...)
else
  redirect_to landing_url(...)
```

This call uses `operator.onboarded?` and is also inside the Stripe Connect
error path — only reachable when `FinishStripeConnect` fails. In that scenario
the operator is actively in the middle of connecting Stripe, so their
`stripe_user_id` will still be nil. After expansion, `onboarded?` returns false
for them, so they land on `landing_url` instead of `modules_url`. Both are
reasonable recovery destinations; there's no user-visible error. The operator
simply needs to retry connecting Stripe.

**Verdict: SAFE — minor redirect destination change in an error recovery flow,
no data loss, no production breakage.**

### 7. `app/views/operator/feed_items/_sidebar.html.erb:192` — SAFE

```erb
<% if !current_location.onboarded? %>
  <%= render(OnboardingSidebar.new(...)) %>
<% end %>
```

Uses **`current_location.onboarded?`** (Location, not Operator). The expansion
targets `Operator#onboarded?` only. This sidebar widget is not affected.

**Verdict: NOT AFFECTED (different receiver).**

### 8. `spec/models/operator_spec.rb:124–134` — NEEDS TEST UPDATE

```ruby
describe '#onboarded?' do
  before do
    create(:plan, operator: operator)
    create(:day_pass_type, operator: operator)
    create(:user, operator: operator, role: :unassigned)
  end

  it 'returns true when all requirements are met' do
    expect(operator.onboarded?).to be true
  end
end
```

The `before` block does not set `operator.stripe_user_id`. After expansion, the
test will fail because `stripe_user_id` is nil. Fix: add
`operator.update!(stripe_user_id: 'acct_test')` (or equivalent factory trait)
inside the `before` block.

**Verdict: TEST UPDATE REQUIRED (not a production risk).**

### 9. `spec/models/location_spec.rb:137–148` — NOT AFFECTED

```ruby
describe '#onboarded?' do
  it 'returns true when all requirements are met' do
    create(:plan, location: location)
    create(:day_pass_type, location: location)
    create(:user, original_location: location, role: :unassigned)
    expect(location.onboarded?).to be true
  end

  it 'returns false when requirements are not met' do
    expect(location.onboarded?).to be false
  end
end
```

Tests `Location#onboarded?`, which is not being changed. No update needed.

**Verdict: NOT AFFECTED.**

## Safety conclusion

**EXPANSION IS SAFE TO PROCEED.**

The two production gating callers (`landing_helper.rb` and
`feed_items_controller.rb`) both have `|| skip_onboarding?` /
`&& !skip_onboarding?` escape hatches. Grandfathered operators with
`skip_onboarding: true` are completely unaffected. Operators without Stripe who
lack that flag will see the wizard prompt — which is exactly the intended
behavior. The only required follow-up work is updating one test expectation in
`spec/models/operator_spec.rb` to add a `stripe_user_id` to the factory setup.
