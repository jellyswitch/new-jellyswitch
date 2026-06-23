# Search/feed indexing is async and best-effort; financial actions commit independently

A committed financial action (refund, charge, invoice status change) must **never** be reported as failed because of a search/feed indexing problem. `FeedItem` indexing is **async** (`searchkick callbacks: :async`, scoped to `FeedItem`), feed-item creation on a financial path is wrapped so an index failure cannot fail the action, OpenSearch transient 5xx are added to the Honeybadger noise filter, and `RefundableFactory.for` returns a `Refundable::NotRefundable` null-object instead of `nil`.

## Context

`operator/refunds#create` committed a refund (Stripe refund + `status = "refunded"`), then synchronously reindexed the new feed item into OpenSearch. When the cluster returned a **502**, `FeedItem#save`'s inline reindex raised, the controller's generic `rescue` flashed "An error occurred", and Honeybadger paged — **even though the money had already moved** (Honeybadger #131903124, invoice 100469). Separately, `RefundableFactory.for` returned `nil` for an already-refunded invoice and the caller did `nil.new` / `nil.cancel`, surfacing the same generic error for a double-refund attempt. The operator-path base controller (unlike the API base) does not disable searchkick callbacks, so every operator-path write of a searchkick model hard-depended on cluster availability.

## Decision

Treat search indexing as a best-effort, out-of-band concern:
1. `FeedItem` indexes async (Sidekiq), so `save` makes no synchronous OpenSearch call. Scoped to `FeedItem` deliberately — not a global `index_mode` change.
2. `Billing::Invoices::Refunds::Save` creates the feed item in a rescue: the refund is committed the moment `invoice.cancel` returns true, and a feed/index failure is logged (warning), never failing the interactor.
3. OpenSearch transient 5xx (`BadGateway` / `ServiceUnavailable` / `GatewayTimeout` / `InternalServerError`) join the `HoneybadgerNoiseFilter`, mirroring the existing Redis-transient suppression. 4xx (bad query/mapping) is **not** suppressed.
4. `RefundableFactory.for` returns `NotRefundable` (a no-op `#cancel` returning false) so callers never crash on a non-refundable invoice.

## Consequences

- **Async indexing depends on the Sidekiq worker.** If it lags, search is briefly stale — but the feed renders from Postgres, so no data is lost or hidden.
- This fix is **independent of the capture-at-booking redesign** and ships first (Phase 0): it stops committed refunds being reported as failures today.
- The invariant generalizes: any future financial side effect that also writes a searchkick model must keep the money commit and the index write decoupled.
