class BackfillBrandAppStoreLinks < ActiveRecord::Migration[7.2]
  # Idempotent backfill of per-brand App Store / Play Store links for the live
  # Jellyswitch brands, so the app-download hand-off (web nudge + onboarding-email
  # badges, both gated on Operator#has_mobile_app_links?) actually renders. URLs
  # were verified against the live store listings (June 2026).
  #
  # Safe by construction: fills only BLANK fields — never clobbers a value an
  # operator set themselves — with one exception: it repairs the known-DEAD Cowork
  # Tahoe Android link (the non-".v2" package returns 404; the live app is ".v2").
  # update_all skips model callbacks/validations (no Searchkick reindex on deploy).
  #
  # All four live brands get both iOS + Android links (Tahoe Longhouse's iOS ID was
  # supplied by the operator once the app cleared App Store review).
  LINKS = {
    "untethered" => {
      ios_url:     "https://apps.apple.com/us/app/untethered-space/id1549473557",
      android_url: "https://play.google.com/store/apps/details?id=com.jellyswitch.untetheredv2",
    },
    "tml" => { # Cowork Tahoe
      ios_url:     "https://apps.apple.com/us/app/cowork-tahoe-the-lab/id1457603889",
      android_url: "https://play.google.com/store/apps/details?id=com.jellyswitch.coworktahoe.v2",
    },
    "choosefolsomworkspace" => {
      ios_url:     "https://apps.apple.com/us/app/choose-folsom-workspace/id6499508578",
      android_url: "https://play.google.com/store/apps/details?id=com.jellyswitch.choosefolsomworkspace",
    },
    "tahoelonghouse" => {
      ios_url:     "https://apps.apple.com/us/app/tahoe-longhouse/id6779449046",
      android_url: "https://play.google.com/store/apps/details?id=com.jellyswitch.tahoelonghouse",
    },
  }.freeze

  COWORK_TAHOE_LIVE_ANDROID =
    "https://play.google.com/store/apps/details?id=com.jellyswitch.coworktahoe.v2".freeze

  def up
    LINKS.each do |subdomain, urls|
      base = Operator.where(subdomain: subdomain)
      urls.each do |column, url|
        base.where(column => [nil, ""]).update_all(column => url)
      end
    end

    # Repair any Cowork Tahoe Android link still pointing at the dead non-".v2"
    # package (404) — leave an already-correct ".v2" value untouched.
    Operator.where(subdomain: "tml")
            .where("android_url LIKE ?", "%id=com.jellyswitch.coworktahoe%")
            .where.not("android_url LIKE ?", "%com.jellyswitch.coworktahoe.v2%")
            .update_all(android_url: COWORK_TAHOE_LIVE_ANDROID)
  end

  def down
    # One-time backfill of public store URLs — nothing meaningful to reverse.
  end
end
