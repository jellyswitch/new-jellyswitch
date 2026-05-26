# == Schema Information
#
# Table name: feed_items
#
#  id          :bigint(8)        not null, primary key
#  blob        :jsonb            not null
#  expense     :boolean          default(FALSE), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#  operator_id :integer          not null
#  user_id     :integer
#
# Indexes
#
#  index_feed_items_on_blob         (blob) USING gin
#  index_feed_items_on_location_id  (location_id)
#
require 'rails_helper'

RSpec.describe FeedItem, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:feed_item_comments) }
    it { should have_many_attached(:photos) }
    it { should have_rich_text(:text) }
  end

  describe 'scopes' do
    describe '.for_operator' do
      it 'returns feed items for the specified operator' do
        operator = create(:operator)
        feed_item = create(:feed_item, operator: operator)
        other_operator = create(:operator)
        other_feed_item = create(:feed_item, operator: other_operator)

        expect(FeedItem.for_operator(operator)).to include(feed_item)
        expect(FeedItem.for_operator(operator)).not_to include(other_feed_item)
      end
    end

    describe '.for_week' do
      it 'returns feed items within the specified date range' do
        week_start = Time.current.beginning_of_week
        week_end = Time.current.end_of_week

        in_range_item = create(:feed_item, created_at: week_start + 1.day)
        out_of_range_item = create(:feed_item, created_at: week_start - 1.day)

        expect(FeedItem.for_week(week_start, week_end)).to include(in_range_item)
        expect(FeedItem.for_week(week_start, week_end)).not_to include(out_of_range_item)
      end
    end

    describe 'type scopes' do
      let!(:feedback) { create(:feed_item, blob: { type: 'feedback' }) }
      let!(:day_pass) { create(:feed_item, blob: { type: 'day-pass' }) }
      let!(:announcement) { create(:feed_item, blob: { type: 'announcement' }) }

      it '.member_feedbacks returns feedback items' do
        expect(FeedItem.member_feedbacks).to include(feedback)
        expect(FeedItem.member_feedbacks).not_to include(day_pass)
      end

      it '.day_passes returns day pass items' do
        expect(FeedItem.day_passes).to include(day_pass)
        expect(FeedItem.day_passes).not_to include(feedback)
      end

      it '.announcements returns announcement items' do
        expect(FeedItem.announcements).to include(announcement)
        expect(FeedItem.announcements).not_to include(feedback)
      end
    end
  end

  describe 'instance methods' do
    let(:feed_item) { create(:feed_item) }

    describe '#action_text' do
      it 'returns appropriate text based on type' do
        feed_item.blob = { type: 'announcement' }
        expect(feed_item.action_text).to eq('posted an announcement')

        feed_item.blob = { type: 'feedback' }
        expect(feed_item.action_text).to eq('sent a message')
      end
    end

    describe '#requires_approval?' do
      it 'returns true for types requiring approval' do
        feed_item.blob = { type: 'subscription' }
        expect(feed_item.requires_approval?).to be true

        feed_item.blob = { type: 'announcement' }
        expect(feed_item.requires_approval?).to be false
      end
    end

    describe '#parse_amount' do
      it 'extracts amount from text content' do
        feed_item = FeedItem.new(blob: {})

        allow(feed_item).to receive(:text).and_return(ActionText::Content.new("The total expense was $123.45 for the event."))

        feed_item.parse_amount
        expect(feed_item.blob['amount']).to eq(12345)
      end
    end

    describe '#is_expense_feed?' do
      it 'is true when the post has both an expense keyword and a dollar amount' do
        feed_item.text = ActionText::Content.new('Spent $5.00 on coffee for the team')
        expect(feed_item.is_expense_feed?).to be true
      end

      it 'is false when the post mentions "spent" with no dollar amount' do
        # Regression: a management note like "We spent the afternoon
        # rearranging the lobby" must not silently become an expense.
        feed_item.text = ActionText::Content.new('We spent the afternoon rearranging the lobby')
        expect(feed_item.is_expense_feed?).to be false
      end

      it 'is false when the post has a dollar amount but no expense keyword' do
        feed_item.text = ActionText::Content.new('New plan launches at $99 next month')
        expect(feed_item.is_expense_feed?).to be false
      end

      it 'is false for a regular post' do
        feed_item.text = ActionText::Content.new('Regular post')
        expect(feed_item.is_expense_feed?).to be false
      end
    end

    describe '#rich_html_body?' do
      it 'is false for a plain-text note (mobile-created)' do
        # ActionText stores plain mobile text verbatim with literal `\n`
        # newlines; the body has no HTML tags. The renderer needs
        # `white-space: pre-wrap` to keep those line breaks visible.
        feed_item.text = ActionText::Content.new("Open at 8am today\n\nNeed wifi fixed")
        expect(feed_item.rich_html_body?).to be false
      end

      it 'is true for a bulleted-list note (Trix/web-created)' do
        # Regression: David's web bullet post rendered with massive vertical
        # gaps between bullets because `pre-wrap` preserved the whitespace
        # between `<li>` tags. Body HTML must be detected as rich so we
        # skip pre-wrap.
        feed_item.text = ActionText::Content.new("<ul><li>one</li><li>two</li></ul>")
        expect(feed_item.rich_html_body?).to be true
      end

      it 'is false when text is blank' do
        feed_item.text = nil
        expect(feed_item.rich_html_body?).to be false
      end
    end
  end

  describe 'lazy relationships' do
    let(:feed_item) { create(:feed_item) }

    describe '#announcement' do
      it 'returns associated announcement' do
        announcement = create(:announcement)
        feed_item.update(blob: { announcement_id: announcement.id })
        expect(feed_item.announcement).to eq(announcement)
      end
    end

    # Similar tests for other lazy relationships
  end
end
