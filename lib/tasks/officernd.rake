namespace :officernd do
  desc "DRY RUN: preview an OfficeRnD CSV import for a location. " \
       "Usage: bin/rails 'officernd:dry_run[/path/to/members.csv, <location_id>]'"
  task :dry_run, %i[csv_path location_id] => :environment do |_t, args|
    csv_path = args[:csv_path]
    location_id = args[:location_id]

    abort "Usage: officernd:dry_run[csv_path, location_id]" if csv_path.blank? || location_id.blank?
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    location = Location.find(location_id)

    ActsAsTenant.with_tenant(location.operator) do
      parsed = Officernd::CsvParser.parse(File.read(csv_path))
      column_mapping = Officernd::ColumnDetector.detect(parsed.headers)

      puts "Location:  ##{location.id} #{location.try(:name)} (operator: #{location.operator.subdomain})"
      puts "Rows:      #{parsed.row_count}"
      puts "Headers:   #{parsed.headers.join(', ')}"
      puts "Detected column mapping:"
      column_mapping.each { |field, header| puts "  #{field.to_s.ljust(20)} <- #{header}" }
      missing = %i[email name] - column_mapping.keys
      puts "  WARNING: no column detected for: #{missing.join(', ')}" if missing.any?
      puts

      result = Onboarding::Import::BuildPreview.call(
        location: location,
        rows: parsed.rows,
        column_mapping: column_mapping,
      )

      unless result.success?
        abort "Preview failed: #{result.message}"
      end

      preview = result.preview
      s = preview[:summary]
      puts "=== DRY RUN SUMMARY (no records written) ==="
      puts "  New members:           #{s[:new]}"
      puts "  Matched to existing:   #{s[:matched_existing]}"
      puts "  Rows with errors:      #{s[:errors]}"
      puts "  Rows with warnings:    #{s[:warnings]}"
      puts

      if preview[:membership_values].any?
        puts "Distinct membership values (map these to Plans in the wizard):"
        preview[:membership_values].each do |m|
          puts "  #{m[:count].to_s.rjust(4)}x  #{m[:value]}"
        end
        puts
      end

      errored = preview[:rows].select { |r| r[:error].present? }
      if errored.any?
        puts "Rows needing attention (first 20):"
        errored.first(20).each do |r|
          puts "  row #{r[:row_number]}: #{r[:error]} (#{r[:email] || r[:name] || 'unknown'})"
        end
      end
    end
  end

  desc "COMMIT: import an OfficeRnD members CSV into a location (idempotent, no Stripe calls). " \
       "Optional PLAN_MAPPING env is JSON of {\"Membership Value\": plan_id}. " \
       "Usage: PLAN_MAPPING='{\"Full Time\":12}' bin/rails 'officernd:import[/path/members.csv, <location_id>]'"
  task :import, %i[csv_path location_id] => :environment do |_t, args|
    csv_path = args[:csv_path]
    location_id = args[:location_id]

    abort "Usage: officernd:import[csv_path, location_id]" if csv_path.blank? || location_id.blank?
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    location = Location.find(location_id)
    plan_mapping = ENV["PLAN_MAPPING"].present? ? JSON.parse(ENV["PLAN_MAPPING"]) : {}

    ActsAsTenant.with_tenant(location.operator) do
      parsed = Officernd::CsvParser.parse(File.read(csv_path))
      column_mapping = Officernd::ColumnDetector.detect(parsed.headers)

      result = Onboarding::Import::Commit.call(
        location: location,
        rows: parsed.rows,
        column_mapping: column_mapping,
        plan_mapping: plan_mapping,
      )

      abort "Import failed: #{result.message}" unless result.success?

      puts "=== IMPORT COMPLETE ==="
      result.report[:summary].sort.each { |k, v| puts "  #{k.to_s.ljust(26)} #{v}" }

      skipped = result.report[:rows].select { |r| r[:action] == :skipped }
      if skipped.any?
        puts "\nSkipped rows (first 20):"
        skipped.first(20).each { |r| puts "  row #{r[:row_number]}: #{r[:notes]} (#{r[:email]})" }
      end
    end
  end

  desc "DRY RUN: preview a historical-invoice backfill. AMOUNT_FORMAT=dollars|cents (default dollars). " \
       "Usage: bin/rails 'officernd:invoices_dry_run[/path/invoices.csv, <location_id>]'"
  task :invoices_dry_run, %i[csv_path location_id] => :environment do |_t, args|
    csv_path = args[:csv_path]
    location_id = args[:location_id]
    abort "Usage: officernd:invoices_dry_run[csv_path, location_id]" if csv_path.blank? || location_id.blank?
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    location = Location.find(location_id)
    amount_format = (ENV["AMOUNT_FORMAT"].presence || "dollars").to_sym

    ActsAsTenant.with_tenant(location.operator) do
      parsed = Officernd::CsvParser.parse(File.read(csv_path))
      column_mapping = Officernd::InvoiceColumnDetector.detect(parsed.headers)

      puts "Rows: #{parsed.row_count}  |  amount_format: #{amount_format}"
      puts "Detected column mapping:"
      column_mapping.each { |field, header| puts "  #{field.to_s.ljust(26)} <- #{header}" }
      puts

      result = Onboarding::Import::BuildInvoicePreview.call(
        location: location, rows: parsed.rows, column_mapping: column_mapping, amount_format: amount_format,
      )
      abort "Preview failed: #{result.message}" unless result.success?

      s = result.preview[:summary]
      puts "=== DRY RUN SUMMARY (no records written) ==="
      puts "  New invoices:       #{s[:new]}"
      puts "  Already imported:   #{s[:existing]}"
      puts "  Rows with errors:   #{s[:errors]}"
      puts "  Rows with warnings: #{s[:warnings]}"
      puts format("  Total amount due:   $%.2f", s[:total_amount_due_cents] / 100.0)
      puts format("  Total amount paid:  $%.2f", s[:total_amount_paid_cents] / 100.0)

      errored = result.preview[:rows].select { |r| r[:error].present? }
      if errored.any?
        puts "\nRows needing attention (first 20):"
        errored.first(20).each { |r| puts "  row #{r[:row_number]}: #{r[:error]} (#{r[:stripe_invoice_id] || r[:number]})" }
      end
    end
  end

  desc "COMMIT: backfill historical invoices (idempotent, no Stripe, no retroactive credits). " \
       "AMOUNT_FORMAT=dollars|cents (default dollars). " \
       "Usage: bin/rails 'officernd:import_invoices[/path/invoices.csv, <location_id>]'"
  task :import_invoices, %i[csv_path location_id] => :environment do |_t, args|
    csv_path = args[:csv_path]
    location_id = args[:location_id]
    abort "Usage: officernd:import_invoices[csv_path, location_id]" if csv_path.blank? || location_id.blank?
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    location = Location.find(location_id)
    amount_format = (ENV["AMOUNT_FORMAT"].presence || "dollars").to_sym

    ActsAsTenant.with_tenant(location.operator) do
      parsed = Officernd::CsvParser.parse(File.read(csv_path))
      column_mapping = Officernd::InvoiceColumnDetector.detect(parsed.headers)

      result = Onboarding::Import::ImportInvoices.call(
        location: location, rows: parsed.rows, column_mapping: column_mapping, amount_format: amount_format,
      )
      abort "Import failed: #{result.message}" unless result.success?

      puts "=== INVOICE IMPORT COMPLETE ==="
      result.report[:summary].sort.each { |k, v| puts "  #{k.to_s.ljust(20)} #{v}" }

      skipped = result.report[:rows].select { |r| r[:action] == :skipped }
      if skipped.any?
        puts "\nSkipped rows (first 20):"
        skipped.first(20).each { |r| puts "  row #{r[:row_number]}: #{r[:notes]} (#{r[:stripe_invoice_id]})" }
      end
    end
  end

  desc "DRY RUN: preview a historical day-pass backfill. " \
       "Usage: bin/rails 'officernd:day_passes_dry_run[/path/day_passes.csv, <location_id>]'"
  task :day_passes_dry_run, %i[csv_path location_id] => :environment do |_t, args|
    csv_path = args[:csv_path]
    location_id = args[:location_id]
    abort "Usage: officernd:day_passes_dry_run[csv_path, location_id]" if csv_path.blank? || location_id.blank?
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    location = Location.find(location_id)

    ActsAsTenant.with_tenant(location.operator) do
      parsed = Officernd::CsvParser.parse(File.read(csv_path))
      column_mapping = Officernd::DayPassColumnDetector.detect(parsed.headers)

      puts "Rows: #{parsed.row_count}"
      puts "Detected column mapping:"
      column_mapping.each { |field, header| puts "  #{field.to_s.ljust(20)} <- #{header}" }
      puts "NOTE: map day-pass type values to DayPassType ids when importing (TYPE_MAPPING)."
      puts

      result = Onboarding::Import::BuildDayPassPreview.call(
        location: location, rows: parsed.rows, column_mapping: column_mapping,
      )
      abort "Preview failed: #{result.message}" unless result.success?

      s = result.preview[:summary]
      puts "=== DRY RUN SUMMARY (no records written) ==="
      puts "  New day passes:     #{s[:new]}"
      puts "  Already imported:   #{s[:existing]}"
      puts "  Rows with errors:   #{s[:errors]}"
      puts
      puts "Distinct day-pass type values (map these to DayPassTypes):"
      result.preview[:type_values].each { |t| puts "  #{t[:count].to_s.rjust(4)}x  #{t[:value]}" }
    end
  end

  desc "COMMIT: backfill historical day passes (idempotent, no Stripe, no welcome-drip/feed side effects). " \
       "TYPE_MAPPING env is JSON of {\"Type Value\": day_pass_type_id}. " \
       "Usage: TYPE_MAPPING='{\"Day Pass\":7}' bin/rails 'officernd:import_day_passes[/path/day_passes.csv, <location_id>]'"
  task :import_day_passes, %i[csv_path location_id] => :environment do |_t, args|
    csv_path = args[:csv_path]
    location_id = args[:location_id]
    abort "Usage: officernd:import_day_passes[csv_path, location_id]" if csv_path.blank? || location_id.blank?
    abort "File not found: #{csv_path}" unless File.exist?(csv_path)

    location = Location.find(location_id)
    type_mapping = ENV["TYPE_MAPPING"].present? ? JSON.parse(ENV["TYPE_MAPPING"]) : {}

    ActsAsTenant.with_tenant(location.operator) do
      parsed = Officernd::CsvParser.parse(File.read(csv_path))
      column_mapping = Officernd::DayPassColumnDetector.detect(parsed.headers)

      result = Onboarding::Import::ImportDayPasses.call(
        location: location, rows: parsed.rows, column_mapping: column_mapping, type_mapping: type_mapping,
      )
      abort "Import failed: #{result.message}" unless result.success?

      puts "=== DAY-PASS IMPORT COMPLETE ==="
      result.report[:summary].sort.each { |k, v| puts "  #{k.to_s.ljust(20)} #{v}" }

      skipped = result.report[:rows].select { |r| r[:action] == :skipped }
      if skipped.any?
        puts "\nSkipped rows (first 20):"
        skipped.first(20).each { |r| puts "  row #{r[:row_number]}: #{r[:notes]}" }
      end
    end
  end
end
