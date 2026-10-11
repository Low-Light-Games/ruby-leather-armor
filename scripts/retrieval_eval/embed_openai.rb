# frozen_string_literal: true

# Embeds the rules retrieval eval set with the production embedding model
# (text-embedding-3-small, DmConfig's default) and writes
# lib/retrieval_eval/rules_vectors.json, so the eval itself re-runs offline and
# free. Only texts without a vector already in the file are sent, so a rerun
# after editing a few queries costs a few hundred tokens.
#
#     ruby scripts/retrieval_eval/embed_openai.rb
#
# Plain Ruby (stdlib only, no Rails, no bundle). OPENAI_API_KEY is read from the
# environment, or else from the repo's .env into this process only; it is never
# printed or written anywhere. Error output shows the HTTP status and OpenAI's
# error code, never the response message (it can echo part of the key).
#
# Vectors are keyed by SHA1 of the exact text embedded. Rule texts mirror
# Rules.all_entries + Rules.embedding_text; if they ever disagree, the eval
# raises StaleFixtures instead of scoring a different corpus.

require "base64"
require "digest"
require "json"
require "net/http"
require "uri"
require "yaml"

MODEL = "text-embedding-3-small"
DIMENSIONS = 1536
PRICE_PER_MILLION_TOKENS = 0.02 # USD, DmConfig::EMBEDDING_MODELS input_cost
BATCH = 100
ROOT = File.expand_path("../..", __dir__)
ENTRIES_DIR = File.join(ROOT, "app/services/rules/entries")
QUERIES_PATH = File.join(ROOT, "lib/retrieval_eval/rules_queries.yml")
OUTPUT_PATH = File.join(ROOT, "lib/retrieval_eval/rules_vectors.json")
DOMAINS = %w[combat traversal social exploration rest inventory magic].freeze # Rules::DOMAINS

def api_key
  from_env = ENV.fetch("OPENAI_API_KEY", "").strip
  return from_env unless from_env.empty?

  env_path = File.join(ROOT, ".env")
  abort "OPENAI_API_KEY is not set and #{env_path} does not exist" unless File.exist?(env_path)

  line = File.foreach(env_path).find { |l| l.match?(/\A\s*(export\s+)?OPENAI_API_KEY\s*=/) }
  key = line&.split("=", 2)&.last.to_s.strip
  key = key[1..-2] if key.size >= 2 && key[0] == key[-1] && ['"', "'"].include?(key[0])
  abort "OPENAI_API_KEY is missing from .env" if key.empty?

  key
end

# Mirrors Rules.all_entries (a slug defined in two domains keeps the later one)
# and Rules.embedding_text.
def rule_texts
  entries = {}
  DOMAINS.each do |domain|
    yaml = YAML.safe_load_file(File.join(ENTRIES_DIR, "#{domain}.yml"), permitted_classes: [Symbol]) || {}
    yaml.each do |slug, data|
      entries[slug] = ["#{data['name']} (#{domain})", data["text"].to_s.strip].join("\n").strip
    end
  end
  entries.values
end

def query_texts
  YAML.safe_load_file(QUERIES_PATH).map { |row| row.fetch("query") }
end

def embed(texts, key)
  uri = URI("https://api.openai.com/v1/embeddings")
  request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{key}")
  request.body = JSON.generate(model: MODEL, input: texts)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.request(request) }
  unless response.is_a?(Net::HTTPSuccess)
    abort "OpenAI embeddings failed: HTTP #{response.code} (#{error_code(response.body)})"
  end

  body = JSON.parse(response.body)
  [body.fetch("data").sort_by { |d| d["index"] }.map { |d| d["embedding"] }, body.dig("usage", "total_tokens").to_i]
end

def error_code(body)
  JSON.parse(body).dig("error", "code") || "no error code"
rescue JSON::ParserError
  "unparseable error body"
end

def pack(vector)
  Base64.strict_encode64(vector.pack("e*"))
end

existing = File.exist?(OUTPUT_PATH) ? JSON.parse(File.read(OUTPUT_PATH)) : {}
vectors = existing["model"] == MODEL ? existing.fetch("vectors", {}) : {}

texts = (rule_texts + query_texts).uniq
wanted = texts.to_h { |text| [Digest::SHA1.hexdigest(text), text] }
missing = wanted.reject { |digest, _| vectors.key?(digest) }

tokens = 0
unless missing.empty?
  key = api_key
  missing.to_a.each_slice(BATCH) do |batch|
    embeddings, used = embed(batch.map(&:last), key)
    tokens += used
    batch.zip(embeddings).each do |(digest, _text), vector|
      abort "unexpected vector size #{vector.size}" unless vector.size == DIMENSIONS
      vectors[digest] = pack(vector)
    end
  end
end

vectors = vectors.slice(*wanted.keys).sort.to_h
fixture = { model: MODEL, dimensions: DIMENSIONS, encoding: "base64 little-endian float32", vectors: vectors }
File.write(OUTPUT_PATH, "#{JSON.generate(fixture)}\n")

puts format("embedded %d new text(s), %d tokens, ~$%.6f; %d vectors in %s",
            missing.size, tokens, tokens * PRICE_PER_MILLION_TOKENS / 1_000_000, vectors.size,
            OUTPUT_PATH.delete_prefix("#{ROOT}/"))
