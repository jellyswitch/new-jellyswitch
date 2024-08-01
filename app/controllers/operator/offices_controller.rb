class Operator::OfficesController < Operator::BaseController
  before_action :find_office, only: [:show, :edit, :update, :destroy]
  before_action :background_image, except: [:create, :update]

  def index
    @offices = current_tenant.offices.order(:name).occupied
    @available_offices = current_tenant.offices.available_for_lease
    @upcoming_renewals = current_tenant.offices.upcoming_renewals(60)
    @archived_offices = current_tenant.offices.archived
    authorize Office
  end

  def show
    authorize @office
  end

  def new
    @office = Office.new
    authorize @office
  end

  def create
    @office = Office.new(office_params)
    authorize @office

    if @office.save
      flash[:notice] = "Office #{@office.name} created."
      turbo_redirect(office_path(@office))
    else
      flash[:error] = "Could not save office"
      render :new, status: 422
    end
  end

  def edit
    authorize @office
  end

  def destroy
    authorize @office, :destroy?

    if @office.destroy
      flash[:notice] = "#{@office.name} deleted."
      redirect_to offices_path
    else
      flash[:error] = "Could not delete office."
      redirect_to office_path(@office)
    end
  end

  def update
    authorize @office

    @office.update(office_params)

    if @office.save
      flash[:notice] = "Office #{@office.name} has been updated."
      turbo_redirect(office_path(@office))
    else
      flash[:error] = "Could not update office"
      render :edit, status: 422
    end
  end

  def available
    @offices = current_tenant.offices.available_for_lease
    authorize Office
  end

  def upcoming_renewals
    @offices = current_tenant.offices.upcoming_renewals(60)
    authorize Office
  end

  def archived
    @offices = current_tenant.offices.archived
    authorize Office
  end

  private

  def find_office(key = :id)
    @office = Office.friendly.find(params[key])
  end

  def office_params
    params.require(:office).permit(:name, :description, :capacity, :square_footage, :photo, :lease, :visible)
  end
end
