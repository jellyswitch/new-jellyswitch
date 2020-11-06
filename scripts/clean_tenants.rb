# This script was run via heroku run rails console and not as a file.

$retained_tenant = Operator.where(name: ["Cowork Tahoe", "The Studio Coworking", "Innogrove", "InSpark Coworking"])

def operator_linked_models
  ApplicationRecord.descendants.select do |model|
    model if model.has_attribute? :operator_id
  end
end

def destroy_operators!
  deletions = Operator.where.not(id: $retained_tenant.ids).destroy_all
  Rails.logger.info "#{deletions.count} operators deleted"
end

def destroy_operator_records_for!(model)
  collection = model.where.not(operator_id: $retained_tenant.ids)
  deletions = collection.delete_all
  Rails.logger.info "#{deletions} #{model} rows deleted"
end

def clean_up_tenant_records!
  operator_linked_models.each do |model|
    Rails.logger.info "Cleaning up #{model}..."
    destroy_operator_records_for!(model)
  end
  destroy_operators!
end
