# frozen_string_literal: true

# Uploads a play log blob field to S3 and returns the S3 URL.
# Keys follow the pattern: play_logs/{play_log_id}/{field_name}.json
#
# Uses AWS_S3_ACCESS_KEY_ID / AWS_S3_SECRET_ACCESS_KEY (non-standard names,
# passed explicitly) so they don't collide with any other AWS config on the host.
#
# Errors are intentionally not rescued — the caller (ShipPlayLogJob) lets them
# propagate so Sidekiq can retry and Sentry captures persistent failures.
class S3PayloadStore
  OBJECT_PREFIX = "play_logs"

  def self.upload(play_log_id:, field_name:, body:)
    new.upload(play_log_id: play_log_id, field_name: field_name, body: body)
  end

  def upload(play_log_id:, field_name:, body:)
    key = "#{OBJECT_PREFIX}/#{play_log_id}/#{field_name}.json"

    client.put_object(
      bucket: bucket,
      key: key,
      body: body,
      content_type: "application/json"
    )

    "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
  end

  private

  def client
    @client ||= Aws::S3::Client.new(
      region: region,
      credentials: Aws::Credentials.new(
        ENV.fetch("AWS_S3_ACCESS_KEY_ID"),
        ENV.fetch("AWS_S3_SECRET_ACCESS_KEY")
      )
    )
  end

  def bucket
    ENV.fetch("AWS_S3_BUCKET")
  end

  def region
    ENV.fetch("AWS_S3_REGION", "us-east-1")
  end
end
