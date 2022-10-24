
class BillableFactory
   def self.for(invoiceable)

    def billable
      if invoiceable.user.bill_to_organization? && invoiceable.user.member_of_organization? && invoiceable.user.organization.present?
        if invoiceable.user.organization.billing_contact.present?
          raise "got here #{billing contact present}"
          invoiceable.user.organization.billing_contact
        else
          raise "got here #{billing contact NOT present}"
          invoiceable.user.organization
        end
      else
        raise "got here #{billing user}"
        invoiceable.user
      end
    end

    end.new(invoiceable)
  end
end