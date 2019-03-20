class PushNotifier
  include Interactor

  def call
    @message = context.message
    @user = context.user
    @operator = context.operator

    validate!
    

    apn = Houston::Client.production # change this
    apn.certificate = cert

    notification = Houston::Notification.new(device: @user.ios_token)
    notification.alert = @message
   
    apn.push(notification)
    puts "Pushed message: #{@message} to device: #{@user.ios_token}"
  end

  def cert
    # refactor to file field on operator
    "-----BEGIN CERTIFICATE-----\nMIIGdzCCBV+gAwIBAgIIEuXe0w8tNKUwDQYJKoZIhvcNAQELBQAwgZYxCzAJBgNV\nBAYTAlVTMRMwEQYDVQQKDApBcHBsZSBJbmMuMSwwKgYDVQQLDCNBcHBsZSBXb3Js\nZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9uczFEMEIGA1UEAww7QXBwbGUgV29ybGR3\naWRlIERldmVsb3BlciBSZWxhdGlvbnMgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkw\nHhcNMTkwMzE3MjI0ODE1WhcNMjAwNDE1MjI0ODE1WjCBuTEzMDEGCgmSJomT8ixk\nAQEMI2NvbS5icmlzdGxlY29uZS5UYWhvZU1vdW50YWluTGFiaU9TMUEwPwYDVQQD\nDDhBcHBsZSBQdXNoIFNlcnZpY2VzOiBjb20uYnJpc3RsZWNvbmUuVGFob2VNb3Vu\ndGFpbkxhYmlPUzETMBEGA1UECwwKTUhKVzlQTUhFNDEdMBsGA1UECgwUWmVuIFNw\nYWNlIExhYnMsIEluYy4xCzAJBgNVBAYTAlVTMIIBIjANBgkqhkiG9w0BAQEFAAOC\nAQ8AMIIBCgKCAQEAs56W2MDhwN9pdofvmtYlETdIxN9TTYIzvn9sJWoUC5e3WOOS\naD7ueql8YH3HShqphMUi1tRkNBjEdEJXaNeFGuEVMinvCKVe4mqSIVjhQ1ftJ0Lu\nRx7PIiOUu+KNhDUdEduw4Lf98aOZ8frBX6iKT/+UqjdC/zMUDYTM3qxKsXd3QMs9\nG2uLpVVfeWXZ73sA1AV3nCsSDgY4KW+KZCcDwNamuDbM8gByaD/7deBbl59KNpj1\nyD4aa3OLiMRACwDYqtEQR/jHyKyri/e9ifqLZGVAWAJGHI98HoC4lVkzH0nh/KM1\ndtCXwv6WBDS3ZTJ4DBRCh6SFVQmSMgHljKsttQIDAQABo4ICojCCAp4wDAYDVR0T\nAQH/BAIwADAfBgNVHSMEGDAWgBSIJxcJqbYYYIvs67r2R1nFUlSjtzCCARwGA1Ud\nIASCARMwggEPMIIBCwYJKoZIhvdjZAUBMIH9MIHDBggrBgEFBQcCAjCBtgyBs1Jl\nbGlhbmNlIG9uIHRoaXMgY2VydGlmaWNhdGUgYnkgYW55IHBhcnR5IGFzc3VtZXMg\nYWNjZXB0YW5jZSBvZiB0aGUgdGhlbiBhcHBsaWNhYmxlIHN0YW5kYXJkIHRlcm1z\nIGFuZCBjb25kaXRpb25zIG9mIHVzZSwgY2VydGlmaWNhdGUgcG9saWN5IGFuZCBj\nZXJ0aWZpY2F0aW9uIHByYWN0aWNlIHN0YXRlbWVudHMuMDUGCCsGAQUFBwIBFilo\ndHRwOi8vd3d3LmFwcGxlLmNvbS9jZXJ0aWZpY2F0ZWF1dGhvcml0eTATBgNVHSUE\nDDAKBggrBgEFBQcDAjAwBgNVHR8EKTAnMCWgI6Ahhh9odHRwOi8vY3JsLmFwcGxl\nLmNvbS93d2RyY2EuY3JsMB0GA1UdDgQWBBTRM9mHWyyh4DBG5IMkNjYBsAtdVDAO\nBgNVHQ8BAf8EBAMCB4AwEAYKKoZIhvdjZAYDAQQCBQAwEAYKKoZIhvdjZAYDAgQC\nBQAwgbIGCiqGSIb3Y2QGAwYEgaMwgaAMI2NvbS5icmlzdGxlY29uZS5UYWhvZU1v\ndW50YWluTGFiaU9TMAUMA2FwcAwoY29tLmJyaXN0bGVjb25lLlRhaG9lTW91bnRh\naW5MYWJpT1Mudm9pcDAGDAR2b2lwDDBjb20uYnJpc3RsZWNvbmUuVGFob2VNb3Vu\ndGFpbkxhYmlPUy5jb21wbGljYXRpb24wDgwMY29tcGxpY2F0aW9uMA0GCSqGSIb3\nDQEBCwUAA4IBAQAx7tRaTRJzXKoI0St3OwObCQEkO/CQ+ZuxGs9JeyRvZGVKM2vQ\n/0yb5DO2uWXu1oRprUvw0qT4cJyMKv5ERCRO//IH4RKx4uTwrB/gxxG6EDD0P4ph\niB1Is1FAzvOjAjxS6lEGnYT3kPZXjgR39pDNdBbS2jxWOmCLUsKN7uQ3+kEiDkVv\nVdKCviEQ7osEfkSgU8qUZySI76au6efB/EWSErSQqryxF0tA6yUVvANMH68DSVCG\nZlFT2h98CPH4Uw/zykvMBzsXIusfauOS2arPSMzdVDn5+dUY0tcxLWpPTirQxlms\nceUA16M8i7ijmJerb7Jh/QStsKvQ8HE+aXpC\n-----END CERTIFICATE-----\n-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAs56W2MDhwN9pdofvmtYlETdIxN9TTYIzvn9sJWoUC5e3WOOS\naD7ueql8YH3HShqphMUi1tRkNBjEdEJXaNeFGuEVMinvCKVe4mqSIVjhQ1ftJ0Lu\nRx7PIiOUu+KNhDUdEduw4Lf98aOZ8frBX6iKT/+UqjdC/zMUDYTM3qxKsXd3QMs9\nG2uLpVVfeWXZ73sA1AV3nCsSDgY4KW+KZCcDwNamuDbM8gByaD/7deBbl59KNpj1\nyD4aa3OLiMRACwDYqtEQR/jHyKyri/e9ifqLZGVAWAJGHI98HoC4lVkzH0nh/KM1\ndtCXwv6WBDS3ZTJ4DBRCh6SFVQmSMgHljKsttQIDAQABAoIBAQCGRXQgPjfEdX4i\nFEYiKhj1gK1ONl/QXheOPTS710t6ywRNV3lXokuluFL40q2KkNnOHYwIqibp5uXc\nvscW4Z1n1YCBymUcwnpmqSHp+cYTEISAyADVe4t9yrlhpl8ByK6dbewQYJpd612m\nTTwG5TfXy4f3om3b1fQUkwSPJJ6FgDctCRhpjX//ovcOc2vedPy2kivIE15fsbSJ\navz91jLricVYKcWpAPX+mafv57xfiFZh/v+37NWp5P4l6Pt3m8SlPtPrYTq1l+tM\nzuGWaPV8oOyocMy9c9EuLcIbVmP7gHkXpcww376Xxgeonp3xztEfkpja8/IlyASn\nEtuJQWMBAoGBANlq7nq/+RY9Om1x2fpEm4s+J5binewLwa5Eo3wjStBRcXOCHMts\nL+eh48LusA6/W9M9dTIJOyXAPiLAh+A+UQqAOZkzIliBWqr+kTjNjR0cp3iKnJg1\nnrSTOUZUQiSjDnyfZYH0t3q3Bdd6AkYUPNmr93PlEEELEM5a1/nQHXh1AoGBANN+\nhdOHpk7Q5YhRA4I6A65mGKQyd6y8fexfNgE3fsK9PuSUQMz0s1z53+I3ZdQGmAiq\n3Z6j/5EKse/QQu4glIGaXzu1cOixXhbUcdm19fI5mV+O1JqtJj4yx/xTaGueeNVs\nYTV/ibgus7QR4oWMBiGlq4G5WkuLFc+eQC7svjhBAoGBAJ2Yzk758sM1FLIakefA\nbYNMRYQwtkpQ5068AElOh79jGbqhuN+Xh03+4kr9m27FNPl1Fgtz94TQyfmE17kr\nUrEq6xVqpF3FPgSuzHOBQ+WzTI2q5AHM9EJuaVjaYKuP6kNZg0nlKk5wdnKPxTAp\nIUajSZaflt2e+MqrvNwfCA21AoGACreZnnt8QPgy+XJphBrefuLrkr5/8//lPaoh\neXRPdxzR6BFfK0OnJyn+X19BSLpA0AegjV5wH/Bzzdw22AxMmjixZLwwCYqbYvrG\n/ipLWUfz7rS1L1Vg37wBCFdNrk5sfxwr3OMmnm+3aYOSgAP1d5UGmN9EpRlaNJgn\nVnlmtkECgYB82SREjIi6zipVJYWGSRDm9MBrkOaxLqqJzsjmKByJFDZEWaLf9v6N\nZUu3VnJw86hDkbqjmO7m3UVtEYpvtCLySgSRCV569UTcHOLoBNjKpZ0v6Pnk9gY9\n28VMZxCQfHVPyDha2beKuN8NZnFO5dAnrBljGDWv8QMuBemFyeZoag==\n-----END RSA PRIVATE KEY-----\n"
  end

  def validate!
    if @message.blank?
      context.fail!(message: "Message can't be blank.")
    end

    if @user.blank?
      context.fail!(message: "User can't be blank.")
    end

    if @user.ios_token.blank?
      context.fail!(message: "User #{@user.slug} has no iOS token.")
    end

    if @operator.push_notification_certificate.blank?
      context.fail!(message: "Operator #{@operator.name} has no push notification certificate.")
    end
  end

end