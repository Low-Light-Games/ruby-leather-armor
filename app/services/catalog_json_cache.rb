# frozen_string_literal: true

# Caches a whole catalog's JSON, versioned by row count + latest updated_at so
# any write invalidates it. On a version change one request rebuilds while the
# rest serve the previous JSON.
class CatalogJsonCache
  TTL = 1.day
  REBUILD_LOCK_TTL = 10.seconds

  def self.fetch(model)
    new(model).fetch
  end

  def initialize(model)
    @model = model
    @key = "catalog_json/#{model.model_name.cache_key}"
  end

  def fetch
    Rails.cache.read(@key, version: version) || rebuild_or_serve_stale
  end

  private

  # race_condition_ttl only covers expiry, not a version change, hence the lock.
  def rebuild_or_serve_stale
    return rebuild! if acquire_rebuild_lock

    stale_json || serialize
  end

  def rebuild!
    serialize.tap { |json| Rails.cache.write(@key, json, version: version, expires_in: TTL) }
  end

  def stale_json
    Rails.cache.read(@key)
  end

  def serialize
    @model.all.to_json
  end

  def acquire_rebuild_lock
    Rails.cache.write(rebuild_lock_key, true, unless_exist: true, expires_in: REBUILD_LOCK_TTL)
  end

  def rebuild_lock_key
    "#{@key}/rebuild_lock/#{version}"
  end

  def version
    @version ||= @model.all.cache_version
  end
end
