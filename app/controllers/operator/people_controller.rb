class Operator::PeopleController < Operator::BaseController
  before_action :background_image, only: [:index]

  STAGE_LABELS = {
    "all" => "All",
    "member" => "Members",
    "day_passer" => "Day-passers",
    "tour_taker" => "Tour-takers",
    "signup_only" => "Signed up",
    "past_member" => "Past members",
    "quiet" => "Quiet",
  }.freeze

  STAGE_BADGE_CLASSES = {
    "member" => "badge-success",
    "day_passer" => "badge-info",
    "tour_taker" => "badge-warning",
    "signup_only" => "badge-light",
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

    @q = params[:q].to_s.strip
    if @q.present?
      like = "%#{@q.downcase}%"
      base_scope = base_scope.where("LOWER(name) LIKE :q OR LOWER(email) LIKE :q", q: like)
    end

    @from = params[:from].to_s
    primary_city_val = current_user.current_location&.city || current_user.original_location&.city
    @primary_city = primary_city_val

    case @from
    when "local"
      base_scope = base_scope.where(home_city: primary_city_val) if primary_city_val.present?
    when "out"
      base_scope = base_scope.where.not(home_city: [nil, primary_city_val])
    when /\Astate:(.+)\z/
      state = Regexp.last_match(1)
      base_scope = base_scope.where(home_state: state) if state.present?
    when "", "any", nil
      # no filter
    else
      # unknown: no filter, don't error
    end

    @available_states = current_tenant.users.visible.non_superadmins
                                      .where.not(home_state: nil)
                                      .distinct
                                      .pluck(:home_state).sort

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
      from: @from,
      q: @q,
      primary_city: @primary_city,
      available_states: @available_states,
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
