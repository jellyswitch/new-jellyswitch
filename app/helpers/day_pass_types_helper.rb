
module DayPassTypesHelper
  def day_pass_type_options(day_pass_types)
    day_pass_types.map do |day_pass_type|
      [
        "#{day_pass_type.name} (#{number_to_currency(day_pass_type.amount_in_cents.to_f / 100.00)})",
        day_pass_type.id,
      ]
    end
  end

  def day_pass_type_params
    p = params.require(:day_pass_type).permit(:name, :amount_in_cents, :available, :visible, :always_allow_building_access, :code, :description, :included_meeting_room_minutes, :overage_rate_in_cents, :quantity, :expires_after_days, :daily_limit, :kind, :featured, :display_order, :features_text)
    convert_showcase_features!(p)
    dollars = Money.from_amount(p[:amount_in_cents].to_i, "USD")
    p[:amount_in_cents] = dollars.cents
    # Convert hours input to minutes
    if p[:included_meeting_room_minutes].present?
      p[:included_meeting_room_minutes] = (p[:included_meeting_room_minutes].to_f * 60).to_i
    else
      p[:included_meeting_room_minutes] = nil
    end
    normalize_office_allowance!(p)
    # Convert dollars to cents for overage rate
    if p[:overage_rate_in_cents].present?
      p[:overage_rate_in_cents] = Money.from_amount(p[:overage_rate_in_cents].to_f, "USD").cents
    else
      p[:overage_rate_in_cents] = 0
    end
    p[:location_id] = current_location.id if current_location
    # Blank form field means unlimited — normalize "" to nil so the
    # numericality validation (allow_nil) doesn't reject it.
    p[:daily_limit] = p[:daily_limit].presence if p.key?(:daily_limit)
    p
  end


  def day_pass_type_update_params
    p = params.require(:day_pass_type).permit(:name, :amount_in_cents, :code, :description, :included_meeting_room_minutes, :overage_rate_in_cents, :quantity, :expires_after_days, :daily_limit, :kind, :featured, :display_order, :features_text)
    convert_showcase_features!(p)
    # Convert dollars input to cents for price
    if p[:amount_in_cents].present?
      p[:amount_in_cents] = Money.from_amount(p[:amount_in_cents].to_f, "USD").cents
    end
    # Convert hours input to minutes
    if p[:included_meeting_room_minutes].present?
      p[:included_meeting_room_minutes] = (p[:included_meeting_room_minutes].to_f * 60).to_i
    else
      p[:included_meeting_room_minutes] = nil
    end
    normalize_office_allowance!(p)
    # Convert dollars to cents for overage rate
    if p[:overage_rate_in_cents].present?
      p[:overage_rate_in_cents] = Money.from_amount(p[:overage_rate_in_cents].to_f, "USD").cents
    else
      p[:overage_rate_in_cents] = 0
    end
    # Blank form field means unlimited — normalize "" to nil so the
    # numericality validation (allow_nil) doesn't reject it.
    p[:daily_limit] = p[:daily_limit].presence if p.key?(:daily_limit)
    p
  end

  # office_room_positions is posted as a top-level field (sibling of
  # day_pass_type[...], not nested inside it — Rails strong params can't
  # whitelist arbitrary room-id keys), so it's read directly rather than via
  # day_pass_type_params/day_pass_type_update_params. to_unsafe_h is safe
  # here: every value is coerced through to_i (never interpolated or mass-
  # assigned to a model), and non-positive entries — a blank field types as
  # 0 — are dropped before they can ever reach DayPassTypeRoom's
  # greater-than-0 position validation. Blank room-id keys are already
  # handled by DayPassType#assign_office_rooms! itself.
  def office_room_positions_params
    raw = params[:office_room_positions]
    return {} if raw.blank?
    raw.to_unsafe_h.to_h { |room_id, position| [room_id, position.to_i] }
       .select { |_, position| position.positive? }
  end

  private

  # Day Office billing default (ADR 0026, decided billing): a zero allowance
  # means overage bills from minute one. The form's Stimulus controller
  # already seeds 0 client-side the moment an admin switches to Day Office;
  # this is the server-side backstop for any submission that skips that JS
  # (API misuse, JS disabled, curl) so the default holds regardless of path.
  def normalize_office_allowance!(p)
    return unless p[:kind] == "day_office" && p[:included_meeting_room_minutes].nil?
    p[:included_meeting_room_minutes] = 0
  end
  # Showcase what's-included lines arrive as a textarea (one per line) and are
  # stored as the features array.
  def convert_showcase_features!(p)
    return unless p.key?(:features_text)

    p[:features] = p.delete(:features_text).to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
  end

end
