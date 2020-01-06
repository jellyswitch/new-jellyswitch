module NotificationHelper
  def send_notification_email
    url = "https://api.mailhatch.io/api/v1/send"
    api_key = "JJQe43a&u=W9F3+t&PkVKZ(^P2uiaH>jkfj%{KVMarnuiT4cKQxR4D4XQ2q2fs&M"

    headers = {"Content-Type": "application/json"}

    body = {
      api_key: api_key,
      to: "dave@jellyswitch.com",
      from: "dave@jellyswitch.com",
      text: "this is a test",
      template: "notification", 
      subject: "Test Notification",
      data: {
        message: "This is a test!",
        operator_name: "Daves Space",
        address: "3079 Harrison Ave, South Lake Tahoe, CA 96150"
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