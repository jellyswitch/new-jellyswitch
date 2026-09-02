require "rails_helper"

RSpec.describe Operator, "Concierge + embed-theme settings" do
  let(:operator) { create(:operator, name: "Cowork Tahoe") }

  describe "copy defaults (work pre-config)" do
    it "falls back to the brand name + a default greeting" do
      expect(operator.concierge_display_name).to eq("Cowork Tahoe")
      expect(operator.concierge_greeting_text).to include("Cowork Tahoe")
    end

    it "uses configured copy when present" do
      operator.update!(concierge_assistant_name: "Tahoe Concierge", concierge_greeting: "Hey there!")
      expect(operator.concierge_display_name).to eq("Tahoe Concierge")
      expect(operator.concierge_greeting_text).to eq("Hey there!")
    end
  end

  describe "shared embed-theme (Concierge + tour widget)" do
    it "inherits brand colors, with sensible fallbacks" do
      operator.update!(primary_color: "112233", accent_color: "445566")
      expect(operator.embed_primary_color).to eq("#112233")
      expect(operator.embed_accent_color).to eq("#445566")
    end

    it "lets an accent override beat the inherited accent, normalized to CSS hex" do
      operator.update!(accent_color: "445566", embed_accent_override: "ff0000")
      expect(operator.embed_accent_color).to eq("#ff0000")

      operator.update!(embed_accent_override: "#00ff00")
      expect(operator.embed_accent_color).to eq("#00ff00")
    end

    it "gives Showcase buttons their own color when set, else the accent" do
      operator.update!(embed_accent_override: "ff0000")
      expect(operator.embed_button_color).to eq("#ff0000")

      operator.update!(showcase_button_color: "16a34a")
      expect(operator.embed_button_color).to eq("#16a34a")
      expect(operator.embed_accent_color).to eq("#ff0000")
    end

    it "rejects an accent override that is not a hex color" do
      operator.embed_accent_override = "blue"
      expect(operator).not_to be_valid
      expect(operator.errors[:embed_accent_override]).to be_present
    end

    it "falls back to a default font and accent when nothing is set" do
      expect(operator.embed_font_family).to include("system-ui")
      expect(operator.embed_accent_color).to eq("#2563eb")
    end
  end
end
