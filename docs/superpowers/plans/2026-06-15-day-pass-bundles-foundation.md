# Day Pass Bundle — Backend Foundation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development, strict superpowers:test-driven-development. Steps use `- [ ]`. Run specs with `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>` (rbenv Ruby 3.3.10; plain `bundle` uses the wrong Ruby).

**Goal:** Model prepaid day-pass bundles (N-Packs) and the redemption ledger, and let an operator/member buy one — without touching the door/access path (Plan 2), guest UI (Plan 3), expiration enforcement (Plan 4), or mobile (Plan 5).

**Architecture (see `CONTEXT.md` → Day Pass Bundle + `docs/adr/0008`):**
- `DayPassType.quantity` (default 1). `quantity: 1` is an ordinary single Day Pass (unchanged); `quantity: N` is an N-Pack.
- Buying an N-Pack creates a **`DayPassBundle`** holding `passes_remaining = N` (one Stripe charge for the SKU price). A single (`quantity: 1`) purchase is unchanged — it still mints a dated `DayPass`.
- Every pass leaving a bundle is a **`DayPassBundleRedemption`** (`kind: entry | guest | admin_restore`). `passes_remaining` is a counter; the ledger is the audit trail. `burn!`/`restore!` are atomic.
- `expires_at` is stored on the bundle but **not enforced yet** (Plan 4); default `nil` = perpetual.

**Tech:** Rails, RSpec + FactoryBot. Migrations: follow the repo's existing migration style; the schema uses `bigint` ids.

---

## Task 1: `DayPassType.quantity`

**Files:**
- Create migration: `db/migrate/<ts>_add_quantity_to_day_pass_types.rb`
- Modify: `app/models/day_pass_type.rb`
- Test: `spec/models/day_pass_type_spec.rb` (append)

- [ ] **Step 1: Write failing spec.** Append inside `RSpec.describe DayPassType`:
```ruby
  describe "quantity / bundles" do
    it "defaults quantity to 1 and is not a bundle" do
      t = create(:day_pass_type, operator: create(:operator))
      expect(t.quantity).to eq(1)
      expect(t.bundle?).to be(false)
    end

    it "is a bundle when quantity > 1" do
      t = create(:day_pass_type, operator: create(:operator), quantity: 5)
      expect(t.bundle?).to be(true)
    end

    it "rejects quantity < 1" do
      t = build(:day_pass_type, operator: create(:operator), quantity: 0)
      expect(t).not_to be_valid
      expect(t.errors[:quantity]).to be_present
    end
  end
```

- [ ] **Step 2: Run, confirm fail** (`bundle?`/`quantity` undefined): `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/models/day_pass_type_spec.rb -e "quantity"`. If the `:day_pass_type` factory needs required attrs, adjust minimally; report it.

- [ ] **Step 3: Migration.** Generate `db/migrate/<timestamp>_add_quantity_to_day_pass_types.rb`:
```ruby
class AddQuantityToDayPassTypes < ActiveRecord::Migration[7.1]
  def change
    add_column :day_pass_types, :quantity, :integer, null: false, default: 1
  end
end
```
Run `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rails db:migrate` (and `db:test:prepare` if the test DB needs it).

- [ ] **Step 4: Model.** In `app/models/day_pass_type.rb` add:
```ruby
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  # A quantity > 1 product is an N-Pack (a Day Pass Bundle); quantity 1 is a
  # single day pass. See CONTEXT.md → Day Pass Bundle.
  def bundle?
    quantity.to_i > 1
  end
```

- [ ] **Step 5: Run, confirm pass.** **Step 6: Commit:**
```
git add db/migrate db/schema.rb app/models/day_pass_type.rb spec/models/day_pass_type_spec.rb
git commit -m "feat: DayPassType.quantity (1 = single pass, N = N-Pack bundle)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `DayPassBundle` model

**Files:**
- Create migration: `db/migrate/<ts>_create_day_pass_bundles.rb`
- Create: `app/models/day_pass_bundle.rb`, `spec/factories/day_pass_bundles.rb`
- Test: `spec/models/day_pass_bundle_spec.rb`

- [ ] **Step 1: Write failing spec** `spec/models/day_pass_bundle_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe DayPassBundle do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator) }
  let(:type) { create(:day_pass_type, operator: operator, location: location, quantity: 5) }

  def bundle(attrs = {})
    DayPassBundle.create!({ user: user, billable: user, operator: operator, location: location,
                            day_pass_type: type, quantity_purchased: 5, passes_remaining: 5,
                            purchased_at: Time.current }.merge(attrs))
  end

  it "is active when it has passes and is not expired" do
    expect(bundle).to be_active
  end

  it "is not active when passes are exhausted" do
    expect(bundle(passes_remaining: 0)).not_to be_active
  end

  it "is expired (and inactive) when expires_at is in the past" do
    b = bundle(expires_at: 1.day.ago)
    expect(b).to be_expired
    expect(b).not_to be_active
  end

  it "is not expired when expires_at is nil (perpetual)" do
    expect(bundle(expires_at: nil)).not_to be_expired
  end

  it "scopes .active to non-empty, non-expired bundles" do
    live = bundle
    bundle(passes_remaining: 0)
    bundle(expires_at: 1.day.ago)
    expect(DayPassBundle.active).to contain_exactly(live)
  end
end
```

- [ ] **Step 2: Run, confirm fail.**

- [ ] **Step 3: Migration** `db/migrate/<ts>_create_day_pass_bundles.rb`:
```ruby
class CreateDayPassBundles < ActiveRecord::Migration[7.1]
  def change
    create_table :day_pass_bundles do |t|
      t.references :user, null: false
      t.references :day_pass_type, null: false
      t.references :location
      t.bigint :operator_id, null: false, default: 1
      t.string :billable_type
      t.bigint :billable_id
      t.integer :quantity_purchased, null: false
      t.integer :passes_remaining, null: false
      t.datetime :expires_at
      t.datetime :purchased_at, null: false
      t.references :invoice
      t.timestamps
    end
    add_index :day_pass_bundles, [:billable_type, :billable_id]
    add_index :day_pass_bundles, :operator_id
  end
end
```
Migrate.

- [ ] **Step 4: Model** `app/models/day_pass_bundle.rb`:
```ruby
class DayPassBundle < ApplicationRecord
  belongs_to :user
  belongs_to :day_pass_type
  belongs_to :location, optional: true
  belongs_to :operator
  belongs_to :billable, polymorphic: true, optional: true
  belongs_to :invoice, optional: true
  has_many :redemptions, class_name: "DayPassBundleRedemption", dependent: :destroy

  acts_as_tenant :operator if respond_to?(:acts_as_tenant)

  validates :quantity_purchased, :passes_remaining,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :active, -> { where("passes_remaining > 0").where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    passes_remaining.to_i > 0 && !expired?
  end
end
```
(If the codebase's tenant macro is `acts_as_scopable`/`acts_as_tenant`, match how `DayPass` declares it — mirror `app/models/day_pass.rb`.)

- [ ] **Step 5: Factory** `spec/factories/day_pass_bundles.rb`:
```ruby
FactoryBot.define do
  factory :day_pass_bundle do
    association :user
    association :day_pass_type
    operator { user.operator }
    billable { user }
    quantity_purchased { 5 }
    passes_remaining { 5 }
    purchased_at { Time.current }
  end
end
```

- [ ] **Step 6: Run, confirm pass. Step 7: Commit** (`db/migrate db/schema.rb app/models/day_pass_bundle.rb spec/...`).

---

## Task 3: Redemption ledger — `DayPassBundleRedemption` + `burn!`/`restore!`

**Files:**
- Create migration: `db/migrate/<ts>_create_day_pass_bundle_redemptions.rb`
- Create: `app/models/day_pass_bundle_redemption.rb`, factory
- Modify: `app/models/day_pass_bundle.rb` (add `burn!`, `restore!`)
- Test: `spec/models/day_pass_bundle_redemption_spec.rb`, extend `day_pass_bundle_spec.rb`

- [ ] **Step 1: Write failing spec.** Append to `spec/models/day_pass_bundle_spec.rb`:
```ruby
  describe "#burn! / #restore!" do
    it "burn! decrements and logs a redemption of the given kind" do
      b = bundle(passes_remaining: 3)
      expect { b.burn!(kind: :guest, performed_by: user, guest_name: "Sam") }
        .to change { b.reload.passes_remaining }.from(3).to(2)
      r = b.redemptions.last
      expect(r.kind).to eq("guest")
      expect(r.guest_name).to eq("Sam")
      expect(r.performed_by).to eq(user)
    end

    it "burn! raises and does not go negative when empty" do
      b = bundle(passes_remaining: 0)
      expect { b.burn!(kind: :entry, performed_by: user) }.to raise_error(DayPassBundle::NoPassesRemaining)
      expect(b.reload.passes_remaining).to eq(0)
    end

    it "restore! increments and logs an admin_restore" do
      b = bundle(passes_remaining: 1)
      admin = create(:user, operator: operator)
      expect { b.restore!(by: admin, reason: "accidental") }
        .to change { b.reload.passes_remaining }.from(1).to(2)
      expect(b.redemptions.last.kind).to eq("admin_restore")
    end
  end
```
And create `spec/models/day_pass_bundle_redemption_spec.rb` with a basic validation test (kind presence/inclusion; belongs_to bundle).

- [ ] **Step 2: Run, confirm fail.**

- [ ] **Step 3: Migration** `create_day_pass_bundle_redemptions`:
```ruby
class CreateDayPassBundleRedemptions < ActiveRecord::Migration[7.1]
  def change
    create_table :day_pass_bundle_redemptions do |t|
      t.references :day_pass_bundle, null: false
      t.bigint :operator_id, null: false, default: 1
      t.string :kind, null: false                # entry | guest | admin_restore
      t.references :performed_by, foreign_key: { to_table: :users }
      t.references :day_pass                       # set for entry redemptions
      t.string :guest_name                         # set for guest redemptions
      t.datetime :redeemed_at, null: false
      t.timestamps
    end
  end
end
```
Migrate.

- [ ] **Step 4: Models.** `app/models/day_pass_bundle_redemption.rb`:
```ruby
class DayPassBundleRedemption < ApplicationRecord
  KINDS = %w[entry guest admin_restore].freeze

  belongs_to :day_pass_bundle
  belongs_to :operator
  belongs_to :performed_by, class_name: "User", optional: true
  belongs_to :day_pass, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :redeemed_at, presence: true
end
```
Add to `app/models/day_pass_bundle.rb`:
```ruby
  class NoPassesRemaining < StandardError; end

  # Spend one pass, logging a redemption. Atomic. `kind` is :entry | :guest.
  # entry redemptions also pass the minted DayPass; guest redemptions pass guest_name.
  def burn!(kind:, performed_by:, guest_name: nil, day_pass: nil)
    with_lock do
      raise NoPassesRemaining if passes_remaining.to_i <= 0
      update!(passes_remaining: passes_remaining - 1)
      redemptions.create!(operator: operator, kind: kind.to_s, performed_by: performed_by,
                          guest_name: guest_name, day_pass: day_pass, redeemed_at: Time.current)
    end
  end

  # Admin adds a pass back (auditable).
  def restore!(by:, reason: nil)
    with_lock do
      update!(passes_remaining: passes_remaining + 1)
      redemptions.create!(operator: operator, kind: "admin_restore", performed_by: by,
                          guest_name: reason, redeemed_at: Time.current)
    end
  end
```
(Reusing `guest_name` to store the restore `reason` keeps the table lean; if a reviewer prefers a separate `note` column, add one — but don't over-build.)

- [ ] **Step 5: Run, confirm pass. Step 6: Commit.**

---

## Task 4: Purchase an N-Pack creates a bundle (one charge)

**Files:**
- Create: `app/interactors/billing/day_pass_bundles/create_bundle.rb` (+ save/charge steps mirroring `Billing::DayPasses::*`)
- Modify: `app/controllers/api/v1/day_passes_controller.rb#create` (branch on `day_pass_type.bundle?`)
- Test: `spec/interactors/billing/day_pass_bundles/create_bundle_spec.rb`, `spec/requests/api/v1/day_pass_bundle_purchase_spec.rb`

**Approach:** When `day_pass_type.bundle?`, do NOT mint a `DayPass`. Instead create a `DayPassBundle` with `passes_remaining = quantity_purchased = day_pass_type.quantity`, charge `amount_in_cents` once via the SAME invoice machinery the single-pass flow uses (`Billing::DayPasses::CreateStripeInvoice` / `ChargeDayPassInvoice`), and link the invoice. Mirror the existing `Billing::DayPasses::CreateDayPass` organizer, swapping `SaveDayPass` for a `SaveBundle` step. Read `app/interactors/billing/day_passes/create_day_pass.rb` + `save_day_pass.rb` + `create_stripe_invoice.rb` first and follow their structure exactly (billable resolution, out_of_band handling, invoice linkage).

- [ ] **Step 1: Failing interactor spec** — `create_bundle_spec.rb`: calling `Billing::DayPassBundles::CreateBundle.call(params: { day_pass_type: type.id }, user_id: user.id, operator:, location:, out_of_band: true)` creates a `DayPassBundle` with `passes_remaining == type.quantity`, `billable == user`, and no `DayPass` rows. (`out_of_band: true` avoids real Stripe — confirm that flag skips charging the way the day-pass specs do; mirror them.)
- [ ] **Step 2: Run, confirm fail.**
- [ ] **Step 3: Implement** the `CreateBundle` organizer + `SaveBundle` interactor (mirror `SaveDayPass`: resolve billable, build `DayPassBundle`, set `passes_remaining`/`quantity_purchased` from `day_pass_type.quantity`, `purchased_at: Time.current`, save; fail with a message on invalid). Reuse the existing invoice/charge steps for the charge.
- [ ] **Step 4: Branch the controller.** In `api/v1/day_passes_controller.rb#create`, after loading `day_pass_type`, if `day_pass_type.bundle?` route to `CreateBundle` (no `date` needed) and render the bundle (`{ id, passes_remaining, day_pass_type_name }`); else keep the existing single-pass path untouched.
- [ ] **Step 5: Request spec** — `POST /api/v1/day_passes` with a `quantity: 5` type creates a bundle (passes_remaining 5), no DayPass; a `quantity: 1` type still creates a DayPass (regression). Stub Stripe/charge as the existing day-pass request specs do (or use a card-on-file + out_of_band path).
- [ ] **Step 6: Run green. Step 7: Commit.**

---

## Final gate (before merge — Plan 1 only)
- [ ] `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec spec/models/day_pass_type_spec.rb spec/models/day_pass_bundle_spec.rb spec/models/day_pass_bundle_redemption_spec.rb spec/interactors/billing/day_pass_bundles spec/requests/api/v1/day_pass_bundle_purchase_spec.rb` green.
- [ ] Do NOT merge yet — burn-on-entry (Plan 2), guest pass (Plan 3), expiration enforcement (Plan 4), and mobile/operator UI (Plan 5) follow. Foundation is shippable/testable on its own (operators can define N-Packs; buying one creates a charged bundle with a redemption ledger and admin restore), but it grants no access until Plan 2.
