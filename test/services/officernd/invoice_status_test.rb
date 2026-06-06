require "test_helper"

class Officernd::InvoiceStatusTest < ActiveSupport::TestCase
  test "passes through canonical statuses" do
    %w[open uncollectible void paid refunded].each do |s|
      assert_equal s, Officernd::InvoiceStatus.normalize(s)
    end
  end

  test "maps common synonyms and is case/format insensitive" do
    assert_equal "paid", Officernd::InvoiceStatus.normalize("Paid")
    assert_equal "open", Officernd::InvoiceStatus.normalize("Past Due")
    assert_equal "open", Officernd::InvoiceStatus.normalize("past_due")
    assert_equal "open", Officernd::InvoiceStatus.normalize("PAST-DUE")
    assert_equal "void", Officernd::InvoiceStatus.normalize("Cancelled")
    assert_equal "void", Officernd::InvoiceStatus.normalize("draft")
  end

  test "returns nil for unrecognized status" do
    assert_nil Officernd::InvoiceStatus.normalize("something weird")
    assert_nil Officernd::InvoiceStatus.normalize(nil)
  end

  test "all mapped values are valid Invoice statuses" do
    assert (Officernd::InvoiceStatus::MAP.values.uniq - Invoice::STATUSES).empty?
    assert_includes Invoice::STATUSES, Officernd::InvoiceStatus::DEFAULT
  end
end
