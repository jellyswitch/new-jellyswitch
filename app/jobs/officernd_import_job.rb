class OfficerndImportJob < ApplicationJob
  queue_as :default

  # Runs the actual import for an OfficerndImport in the background, so large dumps
  # don't tie up a web request. Idempotent and Stripe-safe (the interactors guarantee
  # both), so a retry can't double-charge or duplicate.
  def perform(officernd_import_id)
    import = OfficerndImport.unscoped.find_by(id: officernd_import_id)
    return unless import

    ActsAsTenant.with_tenant(import.operator) do
      result = run(import)

      if result.success?
        import.update!(status: "committed", result_log: result.report)
      else
        import.update!(status: "failed", result_log: { "error" => result.message })
      end
    end
  rescue => e
    import&.update!(status: "failed", result_log: { "error" => "#{e.class}: #{e.message}" })
    raise
  end

  private

  def run(import)
    args = {
      location: import.location || import.operator.locations.first,
      rows: import.parsed&.rows || [],
      column_mapping: import.symbolized_column_mapping,
      amount_format: import.amount_format,
    }

    if import.invoices?
      Onboarding::Import::ImportInvoices.call(args)
    else
      Onboarding::Import::Commit.call(args.merge(plan_mapping: import.plan_mapping))
    end
  end
end
