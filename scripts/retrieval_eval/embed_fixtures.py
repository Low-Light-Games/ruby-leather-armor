"""Embed the rules retrieval eval set with a free, local model.

The eval must never call OpenAI, so rule bodies and eval queries are embedded
once with BAAI/bge-small-en-v1.5 (384-d, ONNX via fastembed) and committed.
Vectors are keyed by SHA1 of the exact text embedded, so the Ruby side detects
any drift between these fixtures and the rule YAML.

    docker run --rm -v "$PWD:/app" -w /app python:3.12-slim sh -c \
      "pip install -q fastembed pyyaml && python scripts/retrieval_eval/embed_fixtures.py"
"""

import hashlib
import json
from pathlib import Path

import yaml
from fastembed import TextEmbedding

MODEL = "BAAI/bge-small-en-v1.5"
ROOT = Path(__file__).resolve().parents[2]
ENTRIES_DIR = ROOT / "app/services/rules/entries"
QUERIES_PATH = ROOT / "lib/retrieval_eval/rules_queries.yml"
OUTPUT_PATH = ROOT / "lib/retrieval_eval/rules_vectors.json"
# Mirrors Rules::DOMAINS: a slug defined in two domains keeps the later one.
DOMAINS = ["combat", "traversal", "social", "exploration", "rest", "inventory", "magic"]


def rule_texts():
    entries = {}
    for domain in DOMAINS:
        path = ENTRIES_DIR / f"{domain}.yml"
        for slug, data in (yaml.safe_load(path.read_text()) or {}).items():
            # Mirrors embed_text_for in lib/tasks/rules.rake.
            entries[slug] = f"{data['name']} ({domain})\n{(data.get('text') or '').strip()}".strip()
    return entries


def digest(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def rounded(vector):
    return [round(float(x), 6) for x in vector]


def main():
    model = TextEmbedding(MODEL)
    documents = list(rule_texts().values())
    queries = [row["query"] for row in yaml.safe_load(QUERIES_PATH.read_text())]

    vectors = {}
    for text, vector in zip(documents, model.passage_embed(documents)):
        vectors[digest(text)] = rounded(vector)
    for text, vector in zip(queries, model.query_embed(queries)):
        vectors[digest(text)] = rounded(vector)

    OUTPUT_PATH.write_text(json.dumps({"model": MODEL, "vectors": vectors}, separators=(",", ":")) + "\n")
    print(f"wrote {len(vectors)} vectors to {OUTPUT_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
