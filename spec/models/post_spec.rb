require 'rails_helper'

RSpec.describe Post, type: :model do
  let(:user) { create(:user) }
  let(:location) { create(:location) }
  let(:post) { create(:post, user: user, location: location) }

  describe 'associations' do
    it { should belong_to(:location) }
    it { should belong_to(:user) }
    it { should have_many(:post_replies) }
    it { should have_rich_text(:content) }
  end

  describe 'delegations' do
    it 'delegates operator to location' do
      expect(post).to delegate_method(:operator).to(:location)
    end
  end

  describe 'custom behaviors' do
    let(:post) { create(:post, user: user, location: location, title: 'Test Post') }

    it 'creates a post with valid attributes' do
      expect(post).to be_valid
    end

    it 'has the correct title' do
      expect(post.title).to eq('Test Post')
    end

    it 'associates with the correct user' do
      expect(post.user).to eq(user)
    end

    it 'associates with the correct location' do
      expect(post.location).to eq(location)
    end
  end
end