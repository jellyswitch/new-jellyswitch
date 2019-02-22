class FeedItemsMailer < ApplicationMailer

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.feed_items_mailer.member_feedback.subject
  #
  def member_feedback(params = {})
    @feed_item = params[:feed_item]
    @user = params[:user]

    mail to: @user.email, subject: "New member feedback"
  end
end
