if ENV["SES_ACCESS_KEY_ID"].present?
  Aws.config.update(
    region: "us-east-1",
    credentials: Aws::Credentials.new(
      ENV["SES_ACCESS_KEY_ID"],
      ENV["SES_SECRET_ACCESS_KEY"]
    )
  )
end

ActionMailer::Base.add_delivery_method :ses, SesDeliveryMethod
