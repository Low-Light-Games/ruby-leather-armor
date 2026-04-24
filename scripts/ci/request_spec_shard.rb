#!/usr/bin/env ruby
# frozen_string_literal: true

abort "usage: ruby scripts/ci/request_spec_shard.rb SHARD_INDEX SHARD_TOTAL" unless ARGV.length == 2

shard_index = Integer(ARGV[0])
shard_total = Integer(ARGV[1])

abort "SHARD_TOTAL must be positive" unless shard_total.positive?
abort "SHARD_INDEX must be between 0 and SHARD_TOTAL - 1" unless shard_index.between?(0, shard_total - 1)

spec_files = Dir.glob("spec/requests/**/*_spec.rb").sort
abort "No request specs found" if spec_files.empty?

shards = Array.new(shard_total) { { weight: 0, files: [] } }

spec_files
  .sort_by { |path| [-File.size(path), path] }
  .each do |path|
    target = shards.min_by { |shard| [shard[:weight], shard[:files].length] }
    target[:files] << path
    target[:weight] += File.size(path)
  end

puts shards.fetch(shard_index).fetch(:files)
