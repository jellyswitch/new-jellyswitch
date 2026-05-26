# == Schema Information
#
# Table name: notes
#
#  id           :bigint(8)        not null, primary key
#  notable_type :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  author_id    :bigint(8)        not null
#  notable_id   :bigint(8)        not null
#  operator_id  :bigint(8)        not null
#
# Indexes
#
#  index_notes_on_author_id                   (author_id)
#  index_notes_on_notable                     (notable_type,notable_id)
#  index_notes_on_operator_id                 (operator_id)
#  index_notes_on_operator_id_and_created_at  (operator_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => users.id)
#  fk_rails_...  (operator_id => operators.id)
#
class Note < ApplicationRecord
  acts_as_tenant :operator

  belongs_to :operator
  belongs_to :notable, polymorphic: true
  belongs_to :author, class_name: "User"

  has_rich_text :body
  validates :body, presence: true

  scope :recent, -> { order(created_at: :desc) }

  after_create :log_activity

  # Yields with the after_create Activity callback disabled. Used by the
  # LeadNote → Note backfill task: each LeadNote already produced its own
  # Activity row at original creation time, so re-firing the callback
  # would double the timeline.
  def self.suppress_log_activity
    prev = Thread.current[:suppress_note_log_activity]
    Thread.current[:suppress_note_log_activity] = true
    yield
  ensure
    Thread.current[:suppress_note_log_activity] = prev
  end

  def to_activity_payload
    {
      "author_user_id" => author_id,
      "author_name" => author&.name,
      "content_preview" => body.to_plain_text.truncate(140),
    }
  end

  private

  # Notes on Users feed the Person-view activity timeline (kind: :note).
  # Notes on other notable types (Organization, etc.) don't appear in any
  # per-Person timeline so we skip the Activity row.
  def log_activity
    return if Thread.current[:suppress_note_log_activity]
    return unless notable_type == "User"
    Activity.log(user: notable, kind: :note, subject: self, operator: operator)
  end
end
