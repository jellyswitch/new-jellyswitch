class Demo::Recreate::MemberFeedbacks
  include Interactor

  delegate :operator, to: :context

  def call
    operator.users.each do |user|
      result = MemberFeedback.create!(
        anonymous: [true, false].sample,
        comment: comments.sample,
        user_id: user.id,
        operator_id: operator.id
      )
      puts result
    end
  end

  private

  def comments
    [
      "Here is a comment",
      "Here is another comment",
      "Hello world!"
    ]
  end
end