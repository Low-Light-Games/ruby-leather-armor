# frozen_string_literal: true

# Cache-aside for the definition catalogs (feats, spells, items) that
# GameDataContext fetches in full on every load of the sheet and play pages:
# ~300 rows serialized to ~175KB of JSON that is identical for every user.
#
# Entries are versioned by the table's count + max(updated_at), so every write
# path (seeds, ops:sync_game_catalogs, items minted mid-adventure by
# Mutations::InventoryMutations) invalidates the entry with no callback to forget.
#
# A version bump makes every in-flight request miss at once. Only the request
# that wins a short lock rebuilds; the others keep serving the previous JSON
# (stale-while-revalidate) instead of stampeding the database.
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

  # Rails' race_condition_ttl only covers TTL expiry, not a version mismatch,
  # which is how this cache is invalidated; hence the explicit lock.
  def rebuild_or_serve_stale
    return rebuild! if acquire_rebuild_lock

    # An unversioned read returns whichever version is stored. On a cold cache
    # there is nothing stale to serve, so render inline without writing.
    Rails.cache.read(@key) || serialize
  end

  def rebuild!
    serialize.tap { |json| Rails.cache.write(@key, json, version: version, expires_in: TTL) }
  end

  def serialize
    @model.all.to_json
  end

  # Scoped to the version so a lock taken for an older version never delays
  # the rebuild of a newer one. If the holder dies, the lock simply expires.
  def acquire_rebuild_lock
    Rails.cache.write("#{@key}/rebuild_lock/#{version}", true, unless_exist: true, expires_in: REBUILD_LOCK_TTL)
  end

  def version
    @version ||= @model.all.cache_version
  end
end
