class MentionsController < ApplicationController
  def index
    subdomain = request.subdomains.first.downcase
    current_tenant = Operator.where(subdomain: subdomain).first
    @users = current_tenant.users.admins

    respond_to do |format|
      format.html
      format.json { render json: @users }
    end
  end
end
