class Operator::MentionsController < Operator::BaseController
  def index
    @users = current_tenant.users.admins
    authorize @users

    respond_to do |format|
      format.html
      format.json
    end
  end
end
