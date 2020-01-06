class MailHatch
  attr_reader :url, :api_key, :operator_name, :address, :brand_color, :debug, :dry_run, :ios_store_url, :google_play_store_url

  def initialize(api_key: "JJQe43a&u=W9F3+t&PkVKZ(^P2uiaH>jkfj%{KVMarnuiT4cKQxR4D4XQ2q2fs&M", brand_color: "#ff9900", 
    debug: false, dry_run: false,
    ios_store_url: "",
    google_play_store_url: "")
    @api_key = api_key
    @url = "https://api.mailhatch.io/api/v1/send"
    @operator_name = operator_name || "Cowork Tahoe"
    @address = address || "3079 Harrison Ave, South Lake Tahoe, CA 96150"
    @brand_color = brand_color
    @debug = debug
    @dry_run = dry_run
    @ios_store_url = ios_store_url
    @google_play_store_url = google_play_store_url
  end

  def announcement(to: "dave@jellyswitch.com", from: "dave@jellyswitch.com", text: "This is a test", subject: "Test announcement")
    body = {
      api_key: api_key,
      to: to,
      from: from,
      text: text,
      template: "notification", 
      theme: "minimal",
      subject: subject,
      ios_store_url: ios_store_url,
      google_play_store_url: google_play_store_url,
      data: {
        message: text,
        title: operator_name,
        address: address,
      },
      design: {
        brand_color: brand_color
      }
    }

    post(body)
  end

  private

  def post(body)
    if debug
      pp "MailHatch URL: #{url}"
      puts "Headers:"
      puts JSON.pretty_generate(headers)
      puts "Body:"
      puts JSON.pretty_generate(body)
    end
    
    if dry_run
      "Dry Run"
    else
      HTTParty.post(url, headers: headers, body: body.to_json )
    end
  end

  def headers
    {"Content-Type": "application/json"}
  end
end