class Operator::PeopleController < Operator::BaseController
  before_action :background_image, only: [:index]

  STAGE_LABELS = {
    "all" => "All",
    "member" => "Members",
    "day_passer" => "Day-passers",
    "tour_taker" => "Tour-takers",
    "past_member" => "Past members",
    "quiet" => "Quiet",
  }.freeze

  STAGE_BADGE_CLASSES = {
    "member" => "badge-success",
    "day_passer" => "badge-info",
    "tour_taker" => "badge-warning",
    "past_member" => "badge-secondary",
    "quiet" => "badge-light",
  }.freeze

  def index
    authorize :person, :index?
    @stage = params[:stage].presence_in(STAGE_LABELS.keys) || "all"
    @owned_by_me = ActiveModel::Type::Boolean.new.cast(params[:owned_by_me]) == true

    base_scope = current_tenant.users.visible.non_superadmins
    base_scope = base_scope.in_stage(@stage) unless @stage == "all"
    base_scope = base_scope.where(point_of_contact_id: current_user.id) if @owned_by_me

    @pagy, @people = pagy(base_scope.includes(:point_of_contact).order(:name), items: 50)
    @last_activity_by_user_id = Activity.where(user_id: @people.map(&:id))
                                        .group(:user_id)
                                        .maximum(:occurred_at)

    respond_to do |format|
      format.html
      format.json { render json: people_json }
    end
  end

  private

  def people_json
    {
      stage: @stage,
      owned_by_me: @owned_by_me,
      page: @pagy.page,
      total_pages: @pagy.pages,
      total_count: @pagy.count,
      people: @people.map { |u| person_json(u) },
    }
  end

  def person_json(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      photo_url: photo_url_for(user),
      lifecycle_stage: user.lifecycle_stage.to_s,
      last_activity_at: @last_activity_by_user_id[user.id]&.iso8601,
      point_of_contact_name: user.point_of_contact&.name,
    }
  end

  def photo_url_for(user)
    return nil unless user.has_profile_photo?
    Rails.application.routes.url_helpers.url_for(user.small_square_profile_photo)
  rescue StandardError
    nil
  end
end
