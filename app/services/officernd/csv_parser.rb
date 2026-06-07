require "csv"

module Officernd
  # Parses an OfficeRnD CSV export (String or IO) into normalized headers + rows.
  #
  #   parsed = Officernd::CsvParser.parse(File.read("members.csv"))
  #   parsed.headers # => ["Name", "Email", ...]
  #   parsed.rows    # => [{ "Name" => "Ada", "Email" => "ada@x.com" }, ...]
  #
  # Notes:
  # - Strips a UTF-8 BOM if present (Excel exports love adding one).
  # - Trims surrounding whitespace from headers and values.
  # - Skips fully-blank rows.
  # - `csv` is a Ruby default gem on 3.3; pin `gem "csv"` when upgrading to Ruby 3.4+.
  class CsvParser
    BOM = "\xEF\xBB\xBF".dup.force_encoding("UTF-8").freeze

    ParsedCsv = Struct.new(:headers, :rows) do
      def empty?
        rows.empty?
      end

      def row_count
        rows.length
      end
    end

    class ParseError < StandardError; end

    def self.parse(source)
      new(source).parse
    end

    def initialize(source)
      @source = source
    end

    def parse
      text = read_text
      table = CSV.parse(text, headers: true, skip_blanks: true)

      headers = (table.headers || []).compact.map { |h| h.to_s.strip }
      rows = table.each_with_object([]) do |csv_row, acc|
        hash = normalize_row(csv_row)
        acc << hash unless hash.values.all? { |v| v.nil? || v == "" }
      end

      ParsedCsv.new(headers, rows)
    rescue CSV::MalformedCSVError => e
      raise ParseError, "Could not parse CSV: #{e.message}"
    end

    private

    def read_text
      raw = @source.respond_to?(:read) ? @source.read : @source.to_s
      raw = raw.dup.force_encoding("UTF-8")
      raw = raw.sub(/\A#{Regexp.escape(BOM)}/, "")
      raw
    end

    def normalize_row(csv_row)
      csv_row.to_h.each_with_object({}) do |(key, value), hash|
        next if key.nil?

        hash[key.to_s.strip] = value.nil? ? nil : value.to_s.strip
      end
    end
  end
end
