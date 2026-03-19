class SesDeliveryMethod
  attr_accessor :settings

  def initialize(settings)
    @settings = settings
    @client = Aws::SES::Client.new
  end

  def deliver!(mail)
    @client.send_raw_email(
      raw_message: { data: mail.to_s }
    )
  end
end
