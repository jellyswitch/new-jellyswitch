# OfficeRnD Import — Onboarding Wizard Plan

Goal: during operator onboarding, let them **upload their OfficeRnD CSV**, run a
guided **sorting/mapping** step (identify customers, map membership types → Plans,
day-pass types → DayPassTypes), preview a **dry run**, then **commit**.

Built on the existing onboarding patterns (step-based controller actions + ERB +
Hotwire/Stimulus + `interactor` gem + ActiveStorage + Sidekiq).

## UX flow (4 steps inside onboarding)

1. **Upload** — `file_field` (ActiveStorage) for the CSV. On submit, parse +
   auto-detect columns, store the blob + detected mapping in session.
2. **Map columns** — table preview (first ~10 rows). For each canonical field
   (email, name, phone, company, stripe_customer_id, membership, status) a dropdown
   pre-selected from `Officernd::ColumnDetector`. Operator confirms/overrides.
3. **Sort categories** — for each distinct value in the `membership` column (and, if
   uploaded, day-pass type column), a dropdown to map → existing `Plan`/`DayPassType`,
   or "create new", or "skip". This is the "identify their membership/daypass types" step.
4. **Preview & commit** — render `Onboarding::Import::BuildPreview` output: counts
   (new vs matched-to-existing-Stripe-customer, warnings, errors), expandable row list,
   unmatched-exceptions list. Button → enqueue `Onboarding::Import::Commit` (Sidekiq),
   poll for completion (mirror `approval_poll_controller.js`).

## Components to build

| Layer | Item | Status |
|---|---|---|
| Service | `Officernd::CsvParser` | ✅ done |
| Service | `Officernd::ColumnDetector` | ✅ done |
| Interactor | `Onboarding::Import::BuildPreview` (dry run) | ✅ done |
| Rake | `officernd:dry_run[csv,location_id]` | ✅ done |
| Interactor | `Onboarding::Import::Commit` (transactional, no-Stripe) | ✅ done |
| Rake | `officernd:import[csv,location_id]` (+ `PLAN_MAPPING` env) | ✅ done |
| Model | `OfficerndImport` (ActiveStorage csv + mapping json + audit) | ✅ done |
| Controller | `Operator::OfficerndImportsController` (new/create/map/sort/preview/commit) | ✅ done |
| Views | upload → map → sort → preview → result (ERB, Bootstrap) | ✅ done |
| Routes | `officernd_imports` resource + member steps | ✅ done |
| Entry point | "Import from an OfficeRnD CSV" button on onboarding Add Members | ✅ done |
| Job | `OfficerndImportJob` (Sidekiq) — commit runs in background | ✅ done |
| Polling | `processing` page + `status` JSON + `officernd_import_poll` Stimulus controller | ✅ done |
| Tests | controller spec + job test (upload→map→preview→commit→poll) — **12 passing** | ✅ done |
| Job | `OfficerndImportJob` (Sidekiq, wraps Commit) | ▢ next |
| Controller | new steps in `operator/onboarding_controller.rb` | ▢ next |
| Routes | `upload_csv`, `map_columns`, `sort_categories`, `preview_import`, `commit_import` | ▢ next |
| Views | ERB for the 4 steps | ▢ next |
| Stimulus | `import_mapping_controller.js` (live preview), reuse poll controller for commit | ▢ next |
| Service | `Officernd::Money` / `InvoiceStatus` / `InvoiceColumnDetector` / `ImportRowHelpers` | ✅ done |
| Interactor | `Onboarding::Import::BuildInvoicePreview` (invoice dry run) | ✅ done |
| Interactor | `Onboarding::Import::ImportInvoices` (backfill, no-Stripe, no credits) | ✅ done |
| Rake | `officernd:invoices_dry_run` / `officernd:import_invoices` | ✅ done |
| Tests | parser/detector/preview/commit + invoice money/status/preview/import — **54 passing** |

> **Running the tests:** use `PARALLEL_WORKERS=1` — at >50 tests Rails forks worker
> processes and the `pg` native gem segfaults on macOS. Never run overlapping `rails
> test` invocations (they deadlock on the shared test DB). RSpec runs single-process.

## Still open (future enhancements)
- "Sort" step for day-pass types (members "sort" covers memberships→Plans today).
- Optional Stimulus controller for live column-mapping preview (plain forms work now).

## Done
- Prior-imports / audit history screen — `index` action + view listing every
  `OfficerndImport` (status, row count, outcome summary, who ran it) with a resume/view
  link per status. Linked from the upload and result pages.

## State handling

Persist intermediate state in a lightweight `OfficerndImport` record (belongs_to
location/operator, ActiveStorage `has_one_attached :csv`, json columns for
`column_mapping`, `plan_mapping`, `daypass_mapping`, `status`, `result_log`). Cleaner
and more debuggable than session-only, and gives an audit trail of what was imported.

## Guardrails carried from the spec

- Dry-run is read-only; commit is transactional + idempotent + **never calls Stripe**.
- Match priority: Stripe Customer ID → email (lowercased, scoped to operator).
- Surface (don't silently drop) unmatched rows and unmapped membership values.
