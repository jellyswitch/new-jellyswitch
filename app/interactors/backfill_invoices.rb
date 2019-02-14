class BackfillInvoices
  include Interactor

  def call
    stripe_invoices = Stripe::Invoice.list()
    stripe_invoices.each do |stripe_invoice|
      result = CreateInvoice.call(stripe_invoice: stripe_invoice)
      if result.success?
        puts "Successfully created invoice #{stripe_invoice.number}"
      else
        puts "Failed to create invoice #{stripe_invoice.number}: #{result.message}"
      end
    end
  end
end