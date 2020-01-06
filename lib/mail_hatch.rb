class MailHatch
  attr_reader :url, :api_key, :operator_name, :address

  def initialize(api_key: "JJQe43a&u=W9F3+t&PkVKZ(^P2uiaH>jkfj%{KVMarnuiT4cKQxR4D4XQ2q2fs&M")
    @api_key = api_key
    @url = "https://api.mailhatch.io/api/v1/send"
    @operator_name = operator_name || "Cowork Tahoe"
    @address = address || "3079 Harrison Ave, South Lake Tahoe, CA 96150"
  end

  def announcement(to: "dave@jellyswitch.com", from: "dave@jellyswitch.com", text: "This is a test", subject: "Test announcement")
    headers = {"Content-Type": "application/json"}

    body = {
      api_key: api_key,
      to: to,
      from: from,
      text: text,
      template: "notification", 
      subject: subject,
      data: {
        message: text,
        operator_name: operator_name,
        address: address,
      }
    }

    response = HTTParty.post(
      url,
      headers: headers,
      body: body.to_json
    )
    response
  end
end