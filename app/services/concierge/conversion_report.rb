module Concierge
  # The Concierge's headline metric, computed entirely from the Activity
  # timeline (no analytics pipeline): of Persons who chatted, what share went
  # on to purchase — versus Persons who never chatted — and the lift between.
  #
  #   Concierge::ConversionReport.new(operator: op).call
  #   => { chatters: {count:, converted:, rate:}, non_chatters: {...},
  #        lift: Float, chatters_within_window: {count:, converted:, rate:} }
  class ConversionReport
    PURCHASE_KINDS = %w[day_pass subscription_started].freeze
    DEFAULT_WINDOW_DAYS = 14

    def initialize(operator:, location: nil, window_days: DEFAULT_WINDOW_DAYS)
      @operator = operator
      @location = location
      @window_days = window_days
    end

    def call
      member_ids   = @operator.users.members.where(archived: [false, nil]).pluck(:id)
      chatter_ids  = chat_activities.distinct.pluck(:user_id) & member_ids
      purchaser_ids = Activity.where(operator: @operator, kind: PURCHASE_KINDS, user_id: member_ids)
                              .distinct.pluck(:user_id)

      chatters     = cohort(chatter_ids, purchaser_ids)
      non_chatters = cohort(member_ids - chatter_ids, purchaser_ids)

      {
        chatters: chatters,
        non_chatters: non_chatters,
        lift: lift(chatters[:rate], non_chatters[:rate]),
        chatters_within_window: windowed(chatter_ids),
      }
    end

    private

    def chat_activities
      scope = Activity.where(operator: @operator, kind: "chat")
      scope = scope.where(subject_type: "Location", subject_id: @location.id) if @location
      scope
    end

    def cohort(ids, purchaser_ids)
      count = ids.size
      converted = (ids & purchaser_ids).size
      { count: count, converted: converted, rate: count.zero? ? 0.0 : converted.to_f / count }
    end

    def lift(chatter_rate, non_chatter_rate)
      return 0.0 if non_chatter_rate.zero?
      chatter_rate / non_chatter_rate
    end

    # Velocity signal: of chatters, how many bought within `window_days` of their
    # FIRST chat (a fairer "the chat drove it" read than lifetime).
    def windowed(chatter_ids)
      return { count: 0, converted: 0, rate: 0.0 } if chatter_ids.empty?

      first_chat_at = chat_activities.where(user_id: chatter_ids).group(:user_id).minimum(:occurred_at)
      purchases_by_user = Activity.where(operator: @operator, kind: PURCHASE_KINDS, user_id: chatter_ids)
                                  .pluck(:user_id, :occurred_at)
                                  .group_by(&:first)

      converted = first_chat_at.count do |user_id, first_at|
        (purchases_by_user[user_id] || []).any? do |(_uid, bought_at)|
          bought_at >= first_at && bought_at <= first_at + @window_days.days
        end
      end

      count = chatter_ids.size
      { count: count, converted: converted, rate: converted.to_f / count }
    end
  end
end
