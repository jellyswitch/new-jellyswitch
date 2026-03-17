class BackfillLocationEmailTemplates < ActiveRecord::Migration[7.0]
  def up
    Operator.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        templates = ProductEmailTemplate.where(operator: operator, location_id: nil)
        next if templates.empty?

        operator.locations.each do |location|
          templates.each do |template|
            new_template = template.dup
            new_template.location = location
            new_template.save!

            # Copy ActionText body if present
            if template.body.present?
              new_template.body = template.body.body
              new_template.save!
            end
          end
        end
      end
    end

    # Remove old operator-level templates (location_id: nil)
    ProductEmailTemplate.where(location_id: nil).destroy_all
  end

  def down
    # Can't perfectly reverse — just remove location-scoped templates
    # and the model will re-seed operator-level defaults
  end
end
