FactoryBot.define do
  factory :user do
    name { Faker::Name.unique.name }
    email { Faker::Internet.unique.safe_email }
    password { 'password' }
    bio { Faker::TvShows::GameOfThrones.quote }

    trait :with_stripe_info do
      after(:create) do |user|
        stripe_token = Stripe::Token.create({
          card: {
            number: '4242424242424242',
            exp_month: 3,
            exp_year: 2020,
            cvc: '314',
          },
        })

        user.stripe_customer_id = user.operator.create_stripe_customer(user).id
        user.save
        stripe_customer = user.stripe_customer
        stripe_customer.source = stripe_token.id
        stripe_customer.save
      end
    end
  end
end
