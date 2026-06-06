class OfficerndImport < ApplicationRecord
  include HasLocation

  belongs_to :operator
  acts_as_tenant :operator
  belongs_to :created_by, class_name: "User", optional: true

  has_one_attached :csv

  KINDS = %w[members invoices].freeze
  STATUSES = %w[pending previewed committing committed failed].freeze
  AMOUNT_FORMATS = %w[dollars cents].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :amount_format, inclusion: { in: AMOUNT_FORMATS }

  scope :recent, -> { order(created_at: :desc) }

  def members?
    kind == "members"
  end

  def invoices?
    kind == "invoices"
  end

  # Canonical fields the operator maps columns onto, per kind.
  def canonical_fields
    if invoices?
      %i[stripe_invoice_id stripe_payment_intent_id stripe_customer_id email
         number amount_due amount_paid status date due_date description]
    else
      %i[email name phone company stripe_customer_id membership status]
    end
  end

  # Parses the attached CSV (memoized). Returns Officernd::CsvParser::ParsedCsv.
  def parsed
    return nil unless csv.attached?

    @parsed ||= Officernd::CsvParser.parse(csv.download)
  end

  # Auto-detect a starting column mapping from the headers, per kind.
  def detect_column_mapping(headers = self.headers)
    detector = invoices? ? Officernd::InvoiceColumnDetector : Officernd::ColumnDetector
    detector.detect(headers).transform_keys(&:to_s)
  end

  # Column mapping with symbol keys, ready to hand to the import interactors.
  def symbolized_column_mapping
    column_mapping.to_h.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v if v.present? }
  end

  # Distinct membership values present in the file (for the "sort" step). Members only.
  def membership_values
    return [] unless members? && parsed

    header = symbolized_column_mapping[:membership]
    return [] if header.blank?

    parsed.rows.filter_map { |row| row[header].to_s.strip.presence }.tally.sort_by { |_v, c| -c }
  end
end
