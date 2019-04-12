require 'rails_helper'

RSpec.describe 'Member signup', type: :system, js: true do
  let(:subdomain) { create(:subdomain) }
  let(:operator) { create(:operator, :with_individual_plans, subdomain: subdomain.subdomain) }

  before do
    ActsAsTenant.default_tenant = operator
  end

  after do
    ActsAsTenant.default_tenant = nil
  end

  context 'paying with card' do
    it 'allows a user to select a plan and become a member' do
      sign_up
      choose_membership
      add_card
      wait_for_approval
    end
  end

  context 'paying out of band' do
    it 'allows a user to select a plan and become a member' do
      sign_up
      choose_membership
      select_pay_out_of_band
      wait_for_approval
    end
  end

  def sign_up
    visit '/'

    find('a[data-acc="signup"]').click

    expect(page).to have_content 'Sign Up'

    within('#new_user') do
      fill_in 'Name', with: 'Jared Rader'
      fill_in 'Email', with: 'jared@rader.com'
      fill_in 'Password', with: 'password'
      fill_in 'Confirm password', with: 'password'
      find('input[data-acc="register"]').click
    end

    expect(page).to have_content 'Welcome!'
  end

  def choose_membership
    find('a[data-acc="new-member"]').click

    expect(page).to have_content 'Become a Member'
  end

  def add_card
    within('#stripe-form') do
      find('#subscription_plan_id option', match: :first).select_option

      fill_stripe_elements('4242424242424242')
      find('input[data-acc="add-payment"]').click
    end
  end

  def fill_stripe_elements(card)
    using_wait_time(15) do
      within_frame('__privateStripeFrame10') do
        card.chars.each do |piece|
          find_field('cardnumber').send_keys(piece)
        end

        find_field('exp-date').send_keys("0122")
        find_field('cvc').send_keys '123'
        find_field('postal').send_keys '19335'
      end
    end
  end

  def select_pay_out_of_band
    within('#stripe-form') do
      find('#subscription_plan_id option', match: :first).select_option
      find('label[for="out_of_band"]').click
      find('input[data-acc="add-payment"]').click
    end
  end

  def wait_for_approval
    expect(page).to have_content "We're excited you're here!"
  end
end
