class BackfillMembershipReEngagementTemplates < ActiveRecord::Migration[7.1]
  # run_re_engagement (the member re-engagement automation) now reads the
  # membership/re_engagement ProductEmailTemplate — which never existed. New
  # locations seed it via RE_ENGAGEMENT_PRODUCTS; backfill it (DISABLED, with the
  # default body) for existing locations via the same idempotent seeder so the
  # workflow can find it. Operators still opt in by enabling the template.
  def up
    require Rails.root.join("db/seeds/welcome_drip_templates")
    delay = ProductEmailTemplate::DEFAULT_DELAYS["membership_re_engagement"]

    Operator.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        operator.locations.find_each do |location|
          ProductEmailTemplate.seed_template(operator, location, "membership", "re_engagement", delay)
        end
      end
    end
  end

  def down
    ProductEmailTemplate.where(product_type: "membership", email_type: "re_engagement").delete_all
  end
end
