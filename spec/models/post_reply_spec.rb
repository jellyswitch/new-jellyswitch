require 'rails_helper'

RSpec.describe PostReply, type: :model do
  describe 'associations' do
    it { should belong_to(:post) }
    it { should belong_to(:user) }
    it { should have_rich_text(:content) }
  end

  describe 'delegations' do
    let(:location) { create(:location) }
    let(:operator) { create(:operator) }
    let(:user) { create(:user) }
    let(:post) { create(:post, location: location) }
    let(:post_reply) { create(:post_reply, post: post, user: user) }

    it 'delegates operator to post' do
      expect(post_reply.operator).to eq(post.operator)
    end

    it 'delegates location to post' do
      expect(post_reply.location).to eq(post.location)
    end
  end
end