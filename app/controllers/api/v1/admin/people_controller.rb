class Api::V1::Admin::PeopleController < Api::V1::Admin::BaseController
  PER_PAGE = 50
  STAGE_KEYS = %w[all member day_passer tour_taker past_member quiet].freeze

  def index
    stage = STAGE_KEYS.include?(params[:stage]) ? params[:stage] : "all"
    page = [params[:page].to_i, 1].max
    owned_by_me = ActiveModel::Type::Boolean.new.cast(params[:owned_by_me]) == true

    base = current_tenant.users.visible.non_superadmins
    base = base.in_stage(stage) unless stage == "all"
    base = base.where(point_of_contact_id: current_api_user.id) if owned_by_me

    from = params[:from].to_s
    primary_city_val = current_api_user.current_location&.city || current_api_user.original_location&.city

    case from
    when "local"
      base = base.where(home_city: primary_city_val) if primary_city_val.present?
    when "out"
      base = base.where.not(home_city: [nil, primary_city_val])
    when /\Astate:(.+)\z/
      state = Regexp.last_match(1)
      base = base.where(home_state: state) if state.present?
    when "", "any", nil
      # no filter
    else
      # unknown: no filter
    end

    available_states = current_tenant.users.visible.non_superadmins
                                     .where.not(home_state: nil)
                                     .distinct
                                     .pluck(:home_state).sort

    total_count = base.count
    total_pages = (total_count.to_f / PER_PAGE).ceil.clamp(1, Float::INFINITY).to_i
    people = base.includes(:point_of_contact).order(:name).offset((page - 1) * PER_PAGE).limit(PER_PAGE)

    last_activity_by_user_id = Activity.where(user_id: people.map(&:id))
                                       .group(:user_id)
                                       .maximum(:occurred_at)

    render json: {
      stage: stage,
      owned_by_me: owned_by_me,
      from: from,
      primary_city: primary_city_val,
      available_states: available_states,
      page: page,
      total_pages: total_pages,
      total_count: total_count,
      people: people.map { |u| person_json(u, last_activity_by_user_id) },
    }
  end

  private

  def person_json(user, last_activity_by_user_id)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      photo_url: photo_url_for(user),
      lifecycle_stage: user.lifecycle_stage.to_s,
      last_activity_at: last_activity_by_user_id[user.id]&.iso8601,
      point_of_contact_name: user.point_of_contact&.name,
      home_city: user.home_city,
      home_state: user.home_state,
    }
  end

  def photo_url_for(user)
    return nil unless user.has_profile_photo?
    Rails.application.routes.url_helpers.url_for(user.small_square_profile_photo)
  rescue StandardError
    nil
  end
end
