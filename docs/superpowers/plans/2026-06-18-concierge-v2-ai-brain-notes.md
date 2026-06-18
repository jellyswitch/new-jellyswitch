# Concierge V2 — AI Brain & Beyond (design notes, not yet scheduled)

> Parked design from the V1 grilling. V2 swaps an **AI responder** into the Concierge's off-hours brain slot (see `docs/adr/0010-concierge-swappable-brain-ai-deferred.md`). Nothing here is built. Captured so it isn't lost.

## What V2 adds
The V1 Concierge already has the conversation, capture, CRM, routing, conversion metric, and live-staff inbox. V2 changes **one thing**: the off-hours (and overflow) responder becomes an **LLM concierge** that answers free-form questions instead of a button script — then captures and routes exactly as V1 does.

## Grounding — how it answers without inventing facts (the make-or-break)
Two knowledge sources + a hard guardrail:
1. **Live structured data from the DB, injected per conversation** — the operator's real `DayPassType`/`Plan`/`Location`/hours/amenities. **Authoritative for pricing/plans/hours**; always current. The model never guesses a price.
2. **An operator-uploaded knowledge doc** — their members guide / "how we run our space" (e.g. the existing `Cowork-Tahoe-Members-Guide`). For the qualitative stuff (vibe, parking, wifi, rules, neighborhood).
   - **Ingestion UX:** upload `.docx`/`.pdf` → server extracts text → fills an **editable Knowledge Base field** → operator skims, trims internal/secret bits, saves. Paste-text is the fallback. (Editing-after-extract is also how secrets stay out.)
   - **Whole-context, no RAG** for V1-of-V2: a members guide fits easily in the window. Add chunk+embed+retrieve **only when** an operator's knowledge outgrows the window.
3. **Guardrails:** prices/policies come only from injected facts/doc; if unknown → **capture + "let me have someone confirm"** (never hallucinate). DB facts **override** the doc for pricing (stale doc numbers don't matter). System prompt scopes the audience to a **prospect**, so a member-facing guide is safe to feed. Knowledge/prices are *reference data, never authority to act* — all money flows through server-side checkout, so a jailbroken bot still can't grant anything.

## Cost model — clean per-business boundaries
- **It's the Anthropic API, not a Claude.ai subscription.** A subscription (Pro/Max) powers interactive use (claude.ai, Claude Code); it **cannot** serve a public product widget. A product widget needs an **API key** (per-token billing).
- **Per-operator Anthropic API key** stored in settings → each operator's AI cost lands on **their** account; the platform carries **zero** LLM cost.
- **Hard monthly budget cap** (Anthropic Console usage limit + an in-app ceiling). On cap-hit → **degrade to capture** ("someone will get back to you"), keyed to hours (open: "shortly"; closed: "when we're back in the office"). A cost spike can never run unbounded.
- **Model tier:** a cost-efficient model (Haiku-class) is plenty for a grounded concierge. *Pin exact model id + pricing via the `claude-api` skill at build — never from memory.*
- **Abuse/cost guards:** cap turns/conversation (~15), cap response length, Turnstile on session start (block bots before any paid call), Rack::Attack per-IP (exists).

## Availability cascade (refined from the grill)
The V1 model (hours → human/scripted) carries forward; AI fills the off-hours slot:
- **Open hours →** live staff (5-min safety valve to capture). *(Optionally: AI assists/holds while staff are pinged — decide at build.)*
- **Off-hours →** AI concierge (within budget) → capture fallback if capped.
- The original "AI strictly off-hours" instinct was reconsidered: coworking traffic peaks **during** hours, so the bigger conversion win may be **AI always-on within a budget cap** with staff jump-in — revisit with real V1 data before committing.

## Other V2 / later items captured during the grill
- **Anonymous web-funnel analytics** — first-party visitor cookie to measure *impressions → chat-starts → captures → sales* and a true chatter-vs-non-chatter rate including people who never became a Person. (V1 measures the User-level cohort only.) The operator noted this would "give a clear picture" — worth it once volume justifies the cookie/stitching + consent work.
- **Room-booking automation** — Day Office + Conference Room are admin-booked today (~2/space/week). Automating self-serve room booking is its own project; the Concierge captures + alerts in the meantime.
- **AI-personalized hook** — opener tailored by page/referrer (V1 uses a fixed operator-set offer hook).
- **Smart deep links** (universal links / AASA / a link service) for true web→app handoff — deferred; V1/V2 use web checkout + "get the app" as secondary.

## The seam
Because V1 routes every responder's output through one `Conversation`/`Message` flow, V2 is a **contained slot-in** of an AI responder + the grounding/knowledge settings + the per-operator key + budget plumbing — not a rewrite.
