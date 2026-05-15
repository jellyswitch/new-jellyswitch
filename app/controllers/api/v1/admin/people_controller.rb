class Api::V1::Admin::PeopleController < Api::V1::Admin::BaseController
  PER_PAGE = 50
  STAGE_KEYS = %w[all member day_passer tour_taker past_member quiet].freeze

  def index
    stage = STAGE_KEYS.include?(params[:stage]) ? params[:stage] : "all"
    page = [params[:page].to_i, 1].max

    base = current_tenant.users.visible.non_superadmins
    base = base.in_stage(stage) unless stage == "all"
    base = base.order(:name)

    total_count = base.count
    total_pages = (total_count.to_f / PER_PAGE).ceil.clamp(1, Float::INFINITY).to_i
    people = base.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

    last_activity_by_user_id = Activity.where(user_id: people.map(&:id))
                                       .group(:user_id)
                                       .maximum(:occurred_at)

    render json: {
      stage: stage,
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
      point_of_contact_name: nil,
    }
  end

  def photo_url_for(user)
    return nil unless user.has_profile_photo?
    Rails.application.routes.url_helpers.url_for(user.small_square_profile_photo)
  rescue StandardError
    nil
  end
end
