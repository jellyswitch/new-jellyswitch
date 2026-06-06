require "test_helper"

class Officernd::CsvParserTest < ActiveSupport::TestCase
  test "parses headers and rows into hashes" do
    csv = "Name,Email\nAda Lovelace,ada@example.com\nGrace Hopper,grace@example.com\n"
    parsed = Officernd::CsvParser.parse(csv)

    assert_equal %w[Name Email], parsed.headers
    assert_equal 2, parsed.row_count
    assert_equal "Ada Lovelace", parsed.rows.first["Name"]
    assert_equal "ada@example.com", parsed.rows.first["Email"]
  end

  test "strips a UTF-8 BOM from the first header" do
    csv = "\xEF\xBB\xBFName,Email\nAda,ada@example.com\n"
    parsed = Officernd::CsvParser.parse(csv)

    assert_equal "Name", parsed.headers.first
    assert_equal "Ada", parsed.rows.first["Name"]
  end

  test "trims surrounding whitespace from headers and values" do
    csv = " Name , Email \n  Ada  ,  ada@example.com  \n"
    parsed = Officernd::CsvParser.parse(csv)

    assert_equal %w[Name Email], parsed.headers
    assert_equal "Ada", parsed.rows.first["Name"]
    assert_equal "ada@example.com", parsed.rows.first["Email"]
  end

  test "skips fully blank rows" do
    csv = "Name,Email\nAda,ada@example.com\n,\nGrace,grace@example.com\n"
    parsed = Officernd::CsvParser.parse(csv)

    assert_equal 2, parsed.row_count
  end

  test "accepts an IO source" do
    io = StringIO.new("Name,Email\nAda,ada@example.com\n")
    parsed = Officernd::CsvParser.parse(io)

    assert_equal 1, parsed.row_count
    assert_equal "Ada", parsed.rows.first["Name"]
  end

  test "raises ParseError on malformed CSV" do
    assert_raises(Officernd::CsvParser::ParseError) do
      Officernd::CsvParser.parse("Name,Email\n\"unterminated,quote\n")
    end
  end
end
