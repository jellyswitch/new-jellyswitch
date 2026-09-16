# Pairs a Garmin watch (the Connect IQ "Jellyswitch Keys" app, garmin/keys in
# the mobile repo) with a member account.
#
# Why a pairing code instead of the phone token: the watch app can't run our
# login UI and has no shared keychain with the phone. So the phone — already
# authenticated — mints a short-lived 6-digit code, the member scrolls it in on
# the wrist, and the watch trades it for its own long-lived bearer token. The
# code is single-use, dies after CODE_TTL, and is stored on the user (a SHA-256
# digest, like login_code_digest) rather than in Rails.cache, because the phone
# and the watch hit different requests — and in production different dynos.
# The resulting token carries `client: "garmin"` so door punches can be
# attributed (DoorsController#unlock) and the client revoked separately later.
class Api::V1::GarminController < Api::V1::BaseController
  skip_before_action :authenticate_api_v1, only: [:pair]

  CODE_TTL  = 10.minutes
  TOKEN_TTL = 1.year

  # POST /api/v1/me/garmin_pairing_code  (phone app, authenticated)
  def pairing_code
    code = mint_code!(current_api_user)
    return render_error("Could not generate a code, try again") if code.nil?

    render json: { code: code, expires_in: CODE_TTL.to_i }
  end

  # POST /api/v1/garmin/pair  { code }  (watch app, unauthenticated)
  def pair
    code = params[:code].to_s.gsub(/\D/, "")
    return render_error("code required") if code.blank?

    user = User.find_by(garmin_pairing_code_digest: digest(code))
    if user.nil? || user.archived? || user.garmin_pairing_code_expires_at.nil? ||
       user.garmin_pairing_code_expires_at <= Time.current
      return render_error("Code not valid", status: :not_found)
    end

    # Single use: burn the code before handing out a token.
    user.update_columns(garmin_pairing_code_digest: nil, garmin_pairing_code_expires_at: nil)

    location = user.original_location || user.current_location
    render json: {
      token:     garmin_token(user),
      name:      user.name,
      operator:  user.operator.name,
      subdomain: user.operator.subdomain,
      location:  location&.name,
    }
  end

  private

  # update_columns: no validations/callbacks — User has a heavy callback chain
  # and this is a side-table write in spirit. The unique index rejects a code
  # another member currently holds; retry a few times on that.
  def mint_code!(user)
    5.times do
      code = format("%06d", SecureRandom.random_number(1_000_000))
      begin
        user.update_columns(
          garmin_pairing_code_digest:     digest(code),
          garmin_pairing_code_expires_at: CODE_TTL.from_now,
        )
        return code
      rescue ActiveRecord::RecordNotUnique
        next
      end
    end
    nil
  end

  def digest(code)
    Digest::SHA256.hexdigest("garmin-pair:#{code}")
  end

  def garmin_token(user)
    payload = {
      user_id:     user.id,
      operator_id: user.operator_id,
      client:      "garmin",
      exp:         TOKEN_TTL.from_now.to_i,
    }
    JWT.encode(payload, jwt_secret, "HS256")
  end
end
