class Operator::OfficerndImportsController < Operator::BaseController
  before_action :authorize_onboarding
  before_action :set_import, only: %i[map update_mapping sort update_sort preview commit processing status result]

  # Audit history of past imports for this operator.
  def index
    @imports = current_tenant.officernd_imports.recent
  end

  # Step 1 — choose kind + upload the CSV.
  def new
    @import = OfficerndImport.new(kind: params[:kind].presence || "members")
  end

  def create
    @import = current_tenant.officernd_imports.new(
      kind: params[:kind].presence || "members",
      location_id: current_location&.id,
      created_by_id: current_user&.id,
      amount_format: params[:amount_format].presence || "dollars",
    )

    unless params[:csv].present?
      flash.now[:error] = "Please choose a CSV file to upload."
      return render :new, status: 422
    end

    # Parse from the raw upload — ActiveStorage doesn't upload the blob until the
    # record is saved, so we can't download it yet.
    raw = params[:csv].read
    params[:csv].rewind
    @import.csv.attach(params[:csv])

    parsed = Officernd::CsvParser.parse(raw)
    @import.headers = parsed.headers
    @import.row_count = parsed.row_count
    @import.column_mapping = @import.detect_column_mapping(parsed.headers)

    if @import.save
      redirect_to map_officernd_import_path(@import)
    else
      flash.now[:error] = @import.errors.full_messages.to_sentence
      render :new, status: 422
    end
  rescue Officernd::CsvParser::ParseError => e
    flash.now[:error] = "Could not read that CSV: #{e.message}"
    render :new, status: 422
  end

  # Step 2 — map CSV columns to canonical fields.
  def map
    @sample_rows = @import.parsed&.rows&.first(8) || []
  end

  def update_mapping
    @import.update!(column_mapping: clean_mapping(params[:column_mapping]))

    if @import.category_values.any?
      redirect_to sort_officernd_import_path(@import)
    else
      redirect_to preview_officernd_import_path(@import)
    end
  end

  # Step 3 (members + day passes) — map distinct category values to Plans / DayPassTypes.
  def sort
    @category_values = @import.category_values
    if @import.day_passes?
      @category_label = "day pass type"
      @category_options = current_tenant.day_pass_types.order(:name).map { |t| [t.name, t.id] }
    else
      @category_label = "plan"
      @category_options = current_tenant.plans.individual.order(:name).map { |p| [p.name, p.id] }
    end
  end

  def update_sort
    @import.update!(plan_mapping: clean_plan_mapping(params[:plan_mapping]))
    redirect_to preview_officernd_import_path(@import)
  end

  # Step 4 — dry-run preview.
  def preview
    @import.update!(status: "previewed") unless @import.status == "committed"
    @preview = build_preview.preview
  end

  # Kick off the import in the background so large dumps don't time out the request.
  def commit
    @import.update!(status: "committing", result_log: {})
    OfficerndImportJob.perform_later(@import.id)
    redirect_to processing_officernd_import_path(@import)
  end

  # Polling page shown while the job runs.
  def processing
    return redirect_to result_officernd_import_path(@import) if @import.status == "committed"
    return redirect_to preview_officernd_import_path(@import) if @import.status == "failed"
    # otherwise render the processing view, which polls #status
  end

  # JSON endpoint the processing page polls.
  def status
    done = %w[committed failed].include?(@import.status)
    redirect =
      case @import.status
      when "committed" then result_officernd_import_path(@import)
      when "failed" then preview_officernd_import_path(@import)
      end

    render json: { status: @import.status, done: done, redirect: redirect }
  end

  # Final result, rendered from the persisted audit log.
  def result
    @report = @import.result_log.deep_symbolize_keys
  end

  private

  def set_import
    @import = current_tenant.officernd_imports.find(params[:id])
  end

  def build_preview
    case @import.kind
    when "invoices"
      Onboarding::Import::BuildInvoicePreview.call(preview_args)
    when "day_passes"
      Onboarding::Import::BuildDayPassPreview.call(preview_args.merge(type_mapping: @import.plan_mapping))
    else
      Onboarding::Import::BuildPreview.call(preview_args.merge(plan_mapping: @import.plan_mapping))
    end
  end

  def run_commit
    case @import.kind
    when "invoices"
      Onboarding::Import::ImportInvoices.call(preview_args)
    when "day_passes"
      Onboarding::Import::ImportDayPasses.call(preview_args.merge(type_mapping: @import.plan_mapping))
    else
      Onboarding::Import::Commit.call(preview_args.merge(plan_mapping: @import.plan_mapping))
    end
  end

  def preview_args
    {
      location: current_location || current_tenant.locations.first,
      rows: @import.parsed&.rows || [],
      column_mapping: @import.symbolized_column_mapping,
      amount_format: @import.amount_format,
    }
  end

  # Keep only canonical field => non-blank header pairs.
  def clean_mapping(raw)
    permitted = @import.canonical_fields.map(&:to_s)
    (raw || {}).to_unsafe_h.slice(*permitted).reject { |_k, v| v.blank? }
  end

  # Keep only membership value => present plan id pairs.
  def clean_plan_mapping(raw)
    (raw || {}).to_unsafe_h.reject { |_k, v| v.blank? }.transform_values(&:to_i)
  end

  def authorize_onboarding
    authorize :onboarding, :show?
  end
end
