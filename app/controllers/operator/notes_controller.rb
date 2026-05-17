class Operator::NotesController < Operator::BaseController
  before_action :require_authentication

  def create
    notable = find_notable
    authorize :note, :create?

    note = notable.notes.new(
      body: note_params[:body],
      author: current_user,
      operator: current_tenant,
    )

    if note.save
      flash[:notice] = "Note added."
    else
      flash[:error] = note.errors.full_messages.to_sentence
    end

    redirect_back fallback_location: notable_redirect_path(notable)
  end

  def destroy
    note = current_tenant.notes.find(params[:id])
    authorize note, :destroy?
    notable = note.notable
    note.destroy
    flash[:notice] = "Note deleted."
    redirect_back fallback_location: notable_redirect_path(notable)
  end

  private

  def note_params
    params.require(:note).permit(:body)
  end

  def find_notable
    case params[:notable_type]
    when "User"
      current_tenant.users.find(params[:notable_id])
    when "Organization"
      current_tenant.organizations.find(params[:notable_id])
    else
      raise ActiveRecord::RecordNotFound, "Unknown notable_type: #{params[:notable_type]}"
    end
  end

  def notable_redirect_path(notable)
    case notable
    when User then user_path(notable)
    when Organization then organization_path(notable)
    else root_path
    end
  end
end
