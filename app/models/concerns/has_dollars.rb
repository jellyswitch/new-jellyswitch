module HasDollars
  extend ActiveSupport::Concern

  class_methods do
    def dollars(*names)
      names.each do |name|
        cents_attr = :"#{name}_in_cents"

        define_method(name) do
          cents = public_send(cents_attr)
          cents.nil? ? nil : cents / 100.0
        end

        define_method("#{name}=") do |value|
          if value.is_a?(String) && value.strip.empty? || value.nil?
            public_send(:"#{cents_attr}=", nil)
          else
            public_send(:"#{cents_attr}=", (BigDecimal(value.to_s) * 100).to_i)
          end
        end
      end
    end
  end
end
