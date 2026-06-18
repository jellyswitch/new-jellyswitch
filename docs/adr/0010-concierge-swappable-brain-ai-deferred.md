# The Concierge is one conversation with a swappable, hours-gated brain — and AI is deferred to V2

The **Concierge** (the website chat widget) is built as a *single conversation flow* whose **responder is pluggable**, selected by the location's business hours:

- **Business hours → live staff** (real person, web + mobile admin inbox), with a **5-minute no-reply safety valve** that degrades to capture.
- **Off-hours → a scripted needs-recommender** (no LLM).

The **AI brain is deliberately NOT in V1.** It is a V2 swap into the off-hours slot, run on a **per-operator Anthropic API key with a hard monthly budget cap**, degrading to capture when the cap is hit. The widget ships with **no LLM dependency, no runtime model cost, and no new real-time infrastructure** in V1.

## Context

The ask was "an AI chat widget that grabs web traffic and converts it." The instinct is to lead with the LLM. But three facts pushed the other way:

1. **Scale.** Five operators use the product. Standing up metered, public, abuse-exposed LLM infrastructure to serve a handful of spaces is premature — the cost/abuse surface (token-burn attacks, prompt injection, budget runaway) is real and unbounded for a public endpoint.
2. **The goal is a measured conversion loop, not a tech demo.** The headline metric is *chatter-vs-non-chatter purchase lift*. You can prove (or disprove) that the widget converts with a **scripted** recommender + live staff — no model required. Build the loop, measure it, *then* invest in the brain.
3. **Cost boundaries.** The operator wants predictable, per-business cost. A Claude.ai subscription cannot serve a public product widget (subscriptions power interactive use, not your customers' web traffic); a product widget needs the **Anthropic API** (per-token billing). Tying each operator to their **own API key + Console budget cap** keeps LLM cost on *their* P&L with a hard ceiling — and keeps the platform's LLM cost at zero.

The existing **tour-request widget** already provides the entire non-AI chassis (embeddable iframe, CORS, Turnstile, honeypot, Rack::Attack, `User` + `Activity` capture, staff push/email alerts), so a scripted Concierge is mostly *assembly*, not new ground.

## Considered Options

- **(a) AI-first V1.** LLM answers from day one. Most impressive demo; highest cost/abuse exposure; unmeasured value; couples the whole feature to a model integration before the conversion loop is proven.
- **(b) Hours-gated AI (AI off-hours, human during hours).** The original instinct. Rejected as the *primary* model because coworking traffic peaks *during* business hours — gating AI off then hands your busiest window to busy floor staff, and instant-answer (the conversion lever) is lost exactly when it matters most. (Retained as a *V2* consideration, but with AI always-on within a budget cap, not clock-gated.)
- **(c) Swappable brain; scripted + live-staff in V1, AI as a V2 slot-in (chosen).** One conversation flow; the responder is human (in hours) or scripted (off hours) now, AI later. Ships without LLM cost, proves the loop, leaves a clean seam for the model.
- **(d) Scripted-only, no live staff.** Leanest. Rejected because a *scripted* brain genuinely under-serves during hours, where a real person converts better — and the operator explicitly wanted human-during-hours.

## Why (c)

1. **It de-risks the expensive, irreversible part.** Model choice, grounding, prompt-injection hardening, and per-operator key management are all V2 concerns we don't pay for until the loop is proven worth it.
2. **The seam is the same for all three brains.** Human, scripted, and AI all produce messages into one `Conversation`; swapping the off-hours responder from scripted → AI is a contained change, not a rebuild.
3. **Cost is bounded by construction.** V1 has no LLM cost at all. V2's cost is a per-operator API key with a Console budget cap, degrading to capture — never an unbounded platform bill.
4. **The metric, not the model, is the point of V1.** Conversion lift is computed from the `Activity` timeline regardless of which brain answered, so V1 already answers "does this widget convert?".

## Consequences

- **V1 builds:** the embeddable + themeable widget shell, a scripted needs-recommender over the operator's real catalog, capture (`User` + `chat` `Activity`), routing (self-serve products → existing checkout; rooms/office → admin alert/tour), a `Conversation`/`Message` model + live staff inbox (web + mobile, polling), business-hours gating with the 5-minute safety valve, and the conversion-lift view.
- **V1 explicitly excludes:** any LLM call, anonymous web-funnel analytics, websockets (polling is sufficient at this scale), and room-booking automation.
- **V2 is a slot-in, not a rewrite:** an AI responder in the off-hours brain, grounded in live DB facts + an operator-uploaded knowledge doc (whole-context, no RAG until docs outgrow the window), behind a **per-operator Anthropic API key + monthly budget cap** that degrades to capture. The catch documented for V2: a Claude.ai subscription **cannot** power this — it requires the Anthropic API.
- **A future reader who asks "why does a 'chat widget' have no AI?"** should read this: it was a sequencing and cost-boundary decision, not an oversight. The brain is swappable on purpose.
