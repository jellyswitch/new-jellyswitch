namespace :email_templates do
  desc "Fill blank-body ProductEmailTemplate rows from Cowork Tahoe's customized templates (DRY_RUN=1 to preview, SOURCE_SUBDOMAIN=tml to override source)"
  task backfill_blanks: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    source_subdomain = ENV["SOURCE_SUBDOMAIN"].presence || "tml"

    source_operator = Operator.find_by(subdomain: source_subdomain)
    abort "Source operator '#{source_subdomain}' not found" unless source_operator

    sources = {}
    source_operator.product_email_templates.with_rich_text_body.each do |t|
      next if t.body.blank?
      key = [t.product_type, t.email_type]
      current = sources[key]
      if current.nil? || t.body.to_plain_text.length > current.body.to_plain_text.length
        sources[key] = t
      end
    end

    puts "Source operator: #{source_operator.name} (#{source_operator.subdomain})"
    puts "Source templates with non-blank body: #{sources.size} (product_type, email_type) combos"

    if sources.empty?
      puts "Nothing to seed from — aborting."
      next
    end

    blanks = ProductEmailTemplate.includes(:operator, :location).select { |t| t.body.blank? }
    puts "Templates with blank body across all operators: #{blanks.size}"
    puts "Mode: #{dry_run ? 'DRY RUN — no changes will be saved' : 'APPLYING CHANGES'}"
    puts

    filled = 0
    skipped_no_source = 0

    blanks.each do |target|
      source = sources[[target.product_type, target.email_type]]
      label = "#{target.operator.subdomain}/#{target.location&.name || 'no-location'} #{target.product_type}/#{target.email_type}"

      if source.nil?
        puts "  - skip (no source)  #{label}"
        skipped_no_source += 1
        next
      end

      puts "  #{dry_run ? '[would fill]' : '[filling]'}     #{label}"
      unless dry_run
        target.update!(body: source.body.to_s)
      end
      filled += 1
    end

    puts
    puts "Summary:"
    puts "  #{dry_run ? 'Would fill' : 'Filled'}: #{filled}"
    puts "  Skipped (no source for product/email_type): #{skipped_no_source}"
  end
end
