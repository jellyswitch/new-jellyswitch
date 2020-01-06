class JellyswitchMail < MailHatch
  attr_reader :operator

  def initialize(operator, dry_run: false)
    @operator = operator
    super(
      api_key: "JJQe43a&u=W9F3+t&PkVKZ(^P2uiaH>jkfj%{KVMarnuiT4cKQxR4D4XQ2q2fs&M",
      brand_color: "#ff9900", 
      debug: true,
      dry_run: dry_run,
      sendgrid_api_key: "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",
      ios_store_url: operator.ios_url,
      google_play_store_url: operator.android_url,
      title: operator.name,
      address: operator.building_address
    )
  end

  def announcement(announcement, recipient)
    async_notification(
      to: "#{recipient.name} <#{recipient.email}>",
      from: "#{announcement.user.name} <#{operator.contact_email}>",
      text: announcement.body,
      subject: "Announcement from #{operator.name}"
    )
  end
end