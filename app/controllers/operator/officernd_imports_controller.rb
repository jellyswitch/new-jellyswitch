class Operator::OfficerndImportsController < Operator::BaseController
  before_action :authorize_onboarding
  before_action :set_import, only: %i[map update_mapping sort update_sort preview commit]

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

    if @import.members? && @import.membership_values.any?
      redirect_to sort_officernd_import_path(@import)
    else
      redirect_to preview_officernd_import_path(@import)
    end
  end

  # Step 3 (members only) — map distinct membership values to Plans.
  def sort
    @membership_values = @import.membership_values
    @plans = current_tenant.plans.individual.order(:name)
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

  def commit
    result = run_commit

    if result.success?
      @import.update!(status: "committed", result_log: result.report)
      @report = result.report
      flash.now[:success] = "Import complete."
      render :result
    else
      @import.update!(status: "failed", result_log: { error: result.message })
      flash.now[:error] = result.message
      @preview = build_preview.preview
      render :preview, status: 422
    end
  end

  private

  def set_import
    @import = current_tenant.officernd_imports.find(params[:id])
  end

  def build_preview
    if @import.invoices?
      Onboarding::Import::BuildInvoicePreview.call(preview_args)
    else
      Onboarding::Import::BuildPreview.call(preview_args.merge(plan_mapping: @import.plan_mapping))
    end
  end

  def run_commit
    if @import.invoices?
      Onboarding::Import::ImportInvoices.call(preview_args)
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
