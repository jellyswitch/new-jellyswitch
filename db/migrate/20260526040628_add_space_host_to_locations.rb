class AddSpaceHostToLocations < ActiveRecord::Migration[7.1]
  # Per-location override for the auto-greeting chat host. When NULL (the
  # default) the existing role-based fallback in `LandingHelper#space_host_for`
  # runs unchanged — that's why no backfill is required.
  #
  # `foreign_key: false` because users and locations are both ActsAsTenant-
  # scoped under operators; a Postgres FK across that boundary would either
  # allow cross-tenant assignment (bad) or require enforcing tenancy in the
  # constraint (complex). Tenancy stays at the app layer.
  #
  # On production: locations is small (~12 rows). Adding a nullable bigint
  # column is a metadata-only ALTER on Postgres — no table rewrite, no
  # row-level lock. The accompanying index is built instantly at this size.
  def change
    add_reference :locations, :space_host, null: true, foreign_key: false, index: true
  end
end
