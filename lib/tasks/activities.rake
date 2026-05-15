namespace :activities do
  desc "Enqueue BackfillActivitiesJob for every operator (bounded to 2 years)"
  task backfill_all: :environment do
    operator_count = Operator.count
    puts "Enqueuing BackfillActivitiesJob for #{operator_count} operator(s)..."

    Operator.find_each do |operator|
      BackfillActivitiesJob.perform_later(operator.id)
      puts "  - enqueued for ##{operator.id} #{operator.name}"
    end

    puts "Done. Workers will run them off the queue."
  end

  desc "Run BackfillActivitiesJob inline for a single operator (debugging)"
  task :backfill, [:operator_id] => :environment do |_, args|
    operator_id = args[:operator_id] || abort("Usage: rake activities:backfill[OPERATOR_ID]")
    operator = Operator.find(operator_id)

    puts "Running backfill inline for ##{operator.id} #{operator.name}..."
    BackfillActivitiesJob.perform_now(operator.id)
    puts "Done. Wrote/skipped activities for the last 2 years."
  end
end
