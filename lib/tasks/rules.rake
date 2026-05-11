# frozen_string_literal: true

namespace :rules do
  desc 'Embed every rule entry from rules/entries into rule_embeddings (idempotent on text_digest).'
  task embed: :environment do
    require 'digest'

    Rules.clear_cache!
    entries = Rules.all_entries

    if entries.empty?
      puts "[rules:embed] no rule entries found at #{Rules::ENTRIES_DIR}"
      next
    end

    ai     = Ai::Client.new(DmConfig.instance)
    model  = DmConfig.instance.narrative_facts_embedding_model
    dims   = DmConfig.instance.narrative_facts_embedding_dimensions

    to_embed = []
    reused = 0

    entries.each do |slug, entry|
      body   = entry[:text].to_s
      brief  = body.split(/\.(\s|\z)/).first&.strip
      brief  = "#{brief}." if brief.present? && !brief.end_with?('.')
      digest = Digest::SHA1.hexdigest("#{slug}|#{entry[:name]}|#{body}")

      existing = RuleEmbedding.find_by(slug: slug)
      if existing && existing.text_digest == digest && existing.embedding.present?
        reused += 1
        next
      end

      to_embed << {
        slug: slug,
        domain: entry[:domain],
        name: entry[:name],
        brief: brief,
        body: body,
        text_digest: digest,
        existing: existing,
        embed_text: embed_text_for(entry)
      }
    end

    if to_embed.empty?
      puts "[rules:embed] all #{reused} rule(s) already embedded with current text — nothing to do."
      next
    end

    texts   = to_embed.map { |r| r[:embed_text] }
    kwargs  = { texts: texts, model: model }
    kwargs[:dimensions] = dims if dims

    puts "[rules:embed] embedding #{to_embed.length} rule(s) (reusing #{reused} unchanged)…"
    vectors = ai.embeddings(**kwargs)

    to_embed.each_with_index do |row, idx|
      vector = vectors[idx]
      attrs  = {
        domain: row[:domain],
        name: row[:name],
        brief: row[:brief],
        body: row[:body],
        text_digest: row[:text_digest],
        embedding: vector
      }

      if row[:existing]
        row[:existing].update!(attrs)
      else
        RuleEmbedding.create!(attrs.merge(slug: row[:slug]))
      end
    end

    puts "[rules:embed] done. embedded=#{to_embed.length} reused=#{reused} total=#{RuleEmbedding.count}"
  end

  desc 'Drop every rule_embeddings row. Useful when changing the embedding model.'
  task reset: :environment do
    n = RuleEmbedding.count
    RuleEmbedding.delete_all
    puts "[rules:reset] cleared #{n} rule embedding row(s)."
  end

  def embed_text_for(entry)
    ["#{entry[:name]} (#{entry[:domain]})", entry[:text].to_s.strip].join("\n").strip
  end
end
