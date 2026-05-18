namespace :users do
  desc "Backfill home_zip from each user's Stripe billing-address postal_code. DRY_RUN=1 to preview, OPERATOR_SUBDOMAIN=tml to scope."
  task backfill_zip_from_stripe: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    operator_subdomain = ENV["OPERATOR_SUBDOMAIN"]

    scope = User.where.not(stripe_customer_id: [nil, ""]).where(home_zip: [nil, ""])
    if operator_subdomain.present?
      op = Operator.find_by(subdomain: operator_subdomain)
      abort "Operator '#{operator_subdomain}' not found" unless op
      scope = scope.where(operator_id: op.id)
    end

    total = scope.count
    puts "Mode: #{dry_run ? 'DRY RUN — no changes will be saved' : 'APPLYING CHANGES'}"
    puts "Scope: #{operator_subdomain.presence || 'all operators'}"
    puts "Users with stripe_customer_id and no home_zip: #{total}"
    next if total.zero?

    updated = 0
    skipped_no_location = 0
    skipped_no_customer = 0
    skipped_no_zip = 0
    api_errors = 0

    scope.find_each.with_index do |user, idx|
      location = user.current_location || user.original_location || user.operator.locations.first
      unless location
        skipped_no_location += 1
        next
      end

      begin
        stripe_customer = location.retrieve_stripe_customer(user)
        if stripe_customer.nil?
          skipped_no_customer += 1
          next
        end

        zip = stripe_customer.try(:address)&.postal_code.presence ||
              stripe_customer.try(:shipping)&.address&.postal_code.presence ||
              stripe_customer.try(:metadata)&.[]("postal_code").presence

        if zip.blank?
          skipped_no_zip += 1
          next
        end

        if dry_run
          puts "  [would set]  user=#{user.id}/#{user.email} → zip=#{zip}"
        else
          user.update_columns(home_zip: zip)
          puts "  [set]        user=#{user.id}/#{user.email} → zip=#{zip}" if (updated % 25).zero?
        end
        updated += 1
      rescue StandardError => e
        api_errors += 1
        Rails.logger.warn("backfill_zip_from_stripe: user=#{user.id} error=#{e.class}: #{e.message}")
      end

      sleep 0.05 # ~20 req/sec — well under Stripe's 100 req/sec limit
      print "." if (idx % 50).zero?
    end

    puts
    puts "Summary:"
    puts "  #{dry_run ? 'Would update' : 'Updated'}: #{updated}"
    puts "  Skipped — no location:       #{skipped_no_location}"
    puts "  Skipped — no Stripe customer: #{skipped_no_customer}"
    puts "  Skipped — no zip in address:  #{skipped_no_zip}"
    puts "  Stripe API errors:            #{api_errors}"
  end
end
