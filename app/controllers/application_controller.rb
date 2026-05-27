
class ApplicationController < ActionController::Base
  layout "application"
  include ApplicationHelper
  include SessionsHelper
  include Pagy::Backend
  include Pundit::Authorization

  skip_forgery_protection

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Pundit denial handler. Splits two cases:
  #
  # 1. Logged-in user actually denied → show the "Whoops" flash so they
  #    know the action wasn't allowed.
  #
  # 2. Anonymous request to a Pundit-protected endpoint → don't flash.
  #    These almost always come from iOS WKWebView link-preview (preview
  #    fetches arrive without session cookies), push-notification deep
  #    links opened after session expiry, or shared URLs. A sticky
  #    "Whoops! That's not allowed" flash gets persisted in the session
  #    cookie and then bleeds into the *next* page load the member opens
  #    in their authenticated app — making perfectly working flows like
  #    Cancel Membership look broken. (Real-world example: Alec Ferguson
  #    at Cowork Tahoe, 2026-05-26: iOS preview of the "Cancel Membership"
  #    link hit /subscriptions/23918, set the Whoops flash on the 302,
  #    and the next /home render surfaced it as if the cancel flow itself
  #    had errored.)
  def user_not_authorized
    if logged_in?
      flash[:alert] = "Whoops! That's not allowed. If this isn't what you were expecting, please contact our staff."
    end
    redirect_to referrer_or_root
  end

  protected

  def include_stripe
    @include_stripe = true
  end

  def referrer_or_root
    request.referrer || root_path
  end

  def turbo_redirect(path, action: "replace")
    @redirect_path = path

    @action = action
    flash.keep
    response.headers["Turbo-Location"] = path
    respond_to do |format|
      format.turbo_stream do
        redirect_to path, status: :see_other, allow_other_host: true
      end
      format.js do
        render "shared/turbo_redirect"
      end
      format.html do
        redirect_to path, allow_other_host: true
      end
    end
  end
end
