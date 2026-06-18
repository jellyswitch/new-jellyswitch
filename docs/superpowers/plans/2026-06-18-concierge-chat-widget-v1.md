# Concierge Chat Widget — V1 Implementation Plan (phased)

> The operator's website chat widget. V1 = **no AI** (see `docs/adr/0010-concierge-swappable-brain-ai-deferred.md`): live staff during business hours + a scripted needs-recommender off-hours, capturing every visitor as a Person and measuring conversion lift. Glossary: `CONTEXT.md` → **Concierge**.
>
> Reuse the **tour-request widget** as the chassis throughout (`app/controllers/embed/tour_requests_controller.rb`, `app/views/embed/tour_requests/*`, `app/views/operator/settings/tour_widget.html.erb`, the `Embed` route namespace, CORS, Turnstile, honeypot, Rack::Attack, `Activity.log`, `TourRequestAlert`). The Concierge is "the tour widget grown a conversation + a recommender + an inbox."
>
> TDD throughout (RSpec: `PATH="$HOME/.rbenv/shims:$PATH" bundle exec rspec <path>`). Spans **two repos**: backend `new-jellyswitch` + mobile `jellyswitch-mobile` (staff inbox).

---

## Phase 1 — Widget shell + scripted recommender + capture + CRM + conversion metric

Goal: a themeable widget an operator embeds; it runs the scripted needs flow, recommends the right product at the operator's real price, captures the Person, routes them, and the operator can see chatter-vs-non-chatter lift. **No live staff, no AI yet.**

### 1.1 — Operator settings + embed snippet + theming
- New `Operator` fields: `concierge_enabled` (bool), `concierge_greeting` (string), `concierge_offer_text` (string, optional — the day-pass promo hook), `concierge_promo_code` (string, optional), `concierge_color` (string hex), `concierge_font` (string). Migration (see `migrations` skill — additive, nullable).
- Settings page `/operator/settings/concierge` mirroring `tour_widget.html.erb`: enable toggle, greeting + offer copy, color/font pickers, **copy-paste embed snippet**, live preview iframe (reuse the signed-preview-token pattern).
- Theming renders into the widget's CSS (color → accent vars; font → `font-family`).

### 1.2 — The embeddable widget (public, framed)
- `Embed::ConciergeController#show` under the `Embed` namespace, served at `/embed/concierge/:operator_subdomain` (+ `/locations/:location_id` pinning, like the tour widget). `X-Frame-Options: ALLOWALL` + CSP strip (copy the tour controller's after-action).
- The widget UI: a corner bubble + **proactive teaser** (appears after ~5s / on scroll / on exit-intent — *not* an auto-open modal; smaller/later on mobile) surfacing `concierge_greeting`/`concierge_offer_text`.
- It is a small JS app inside the iframe driving the scripted flow (button choices + free-text capture). State machine, not an LLM.

### 1.3 — The scripted needs-recommender
- Opening: **"What brings you in today?"** → buttons mapped to needs → products **pulled live from the operator's real catalog** (so price is real and current):
  | Button | Product source | Path |
  |---|---|---|
  | Drop in for a day | cheapest single `DayPassType` (quantity 1) | self-serve |
  | A few days / a week | a `DayPassType` with `quantity > 1` (bundle) | self-serve |
  | Ongoing workspace | a `Plan` (membership) | self-serve |
  | Private office for a day (**Day Office**) | capture-only | admin alert |
  | Team meeting (**Conference Room**) | capture-only | admin alert |
  | Long-term office | capture-only | admin alert + **tour** |
  | Just a question | a small operator-authored FAQ (key/value) + capture | nurture |
- Recommends **one best-fit** with its real price + a single CTA — never a menu.

### 1.4 — Capture + CRM (the conversion event)
- Capture email at the **value moment** (to send the link / save the spot / route to checkout) + **exit-intent** soft capture. No gating form.
- On capture: `User.find_or_initialize_by(email:, operator:)` (same path as the tour widget) + `Activity.log(kind: :chat, user:, operator:, subject: location, payload: { transcript, intent, recommended_product, source: "concierge" })`. **New `Activity` kind `:chat`.**
- Marketing consent + TOS at capture (reuse signup's `terms_accepted` / `marketing_opt_in` semantics).
- Transcript renders in the existing **CRM Activity timeline** (`activity_timeline_helper.rb` — add `chat` to a bucket).

### 1.5 — Routing
- **Self-serve (day pass / bundle / membership):** capture → create lead `User` → route to the existing signup/purchase flow **pre-filled** with email + selected product. *(Build note: verify a public web path to signup+buy exists; if app-only today, wire a thin public entry — this is the one real gap; it can also slip to Phase 3.)*
- **Admin-handled (day office / conference room / office):** capture → `SendNotificationsJob.perform_later(activity, "ConciergeAlert")` → push/email to location managers (mirror `TourRequestAlert`). Office also creates the existing tour-request path.

### 1.6 — Conversion-lift metric
- A funnel card in the operator dashboard, computed from `Activity`:
  - Cohort A = Persons with a `chat` Activity; B = Persons without.
  - Conversion = first purchase Activity (`day_pass` / `subscription`) **within 14 days** (windowed) + lifetime.
  - Render: `Chatted: N → bought M (x%) · Didn't: … · Lift = ×`.
- Also surface the soft funnel stage (chat → account created → sale) since both are tracked.

### Phase 1 anti-spam / reuse
- Rack::Attack `/embed/*` throttle, honeypot, Turnstile on capture — all already exist; point them at the new endpoint.

---

## Phase 2 — Live staff chat (web + mobile)

Goal: during business hours, a real person answers in the widget; off-hours stays scripted; the 5-minute safety valve protects against dead air.

### 2.1 — Conversation + Message model
- `Conversation` (operator, location, nullable `user_id`, anonymous `session_token`, `status: open|staffed|captured|closed`, `last_visitor_at`, `last_staff_at`). `Message` (conversation, `role: visitor|staff|bot`, `body`, `author_id` nullable). Tenant-scoped.
- Link `Conversation.user_id` when the visitor is captured.

### 2.2 — Hours gating + the 5-minute safety valve
- On first visitor message: if **location is open now** (reuse location working-hours logic — note the working-time validation gotcha) → status `open`, post the instant auto-greeting ("usually a few minutes"), `SendNotificationsJob(... "ConciergeAlert")` to staff.
- A scheduled check (or per-poll check): if `open` and **no staff reply within 5 min** → degrade to capture ("the team's tied up — leave your email").
- **Off-hours** → the scripted brain handles it fully (Phase 1 flow) + capture.

### 2.3 — Visitor transport (polling)
- Widget polls `GET /embed/concierge/:subdomain/conversations/:token/messages?since=…` every few seconds for new staff/bot messages. **No websockets** (fine at this scale; ActionCable is bare).
- `POST …/messages` for visitor messages (Rack::Attack throttled).

### 2.4 — Staff inbox — web
- An operator inbox view (list of open conversations + a thread view + reply box) under `/operator/...`. Push alert deep-links here.

### 2.5 — Staff inbox — mobile (`jellyswitch-mobile`)
- A "Chats" screen + thread/reply view in the admin app (phone-first staff). New `conciergeAPI` (list conversations, fetch messages, send reply). Push notification on new visitor message routes to the thread (reuse the deep-link routing pattern).

---

## Phase 3 — Self-serve checkout handoff (smooth the buy)

Goal: make the self-serve products genuinely 1-tap-to-purchase from the recommendation.

- Verify/wire the **public web account-creation → checkout** path for day pass (then bundle, then membership) — pre-fill email + product, finalize password + payment on the existing checkout. Reuse `Users::Create` + `Billing::DayPasses::CreateDayPass` + the bundle/subscription interactors (no new billing).
- "Get the app" as the **secondary** CTA after purchase.
- Confirm the conversion metric now captures widget-attributed sales end-to-end.

---

## Final gates
- Per phase: RSpec green; manual embed test on a real external page (framing, theming, capture, routing); CRM timeline shows the transcript; the lift card renders with seeded data.
- Privacy: transcripts are tenant-scoped PII; never-captured anonymous conversations get a short retention; marketing consent captured at email.
- **Out of scope (V2 — see notes):** AI brain, anonymous web-funnel analytics, room-booking automation, websockets.
