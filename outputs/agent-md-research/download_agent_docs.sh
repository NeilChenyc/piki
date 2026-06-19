#!/usr/bin/env bash
set -euo pipefail
BASE="/Users/a99/localDocuments/codeBase/ideaWorkplace/piki/outputs/agent-md-research/repos"
mkdir -p "$BASE"

repos=(
  "SamurAIGPT/llm-wiki-agent"
  "nvk/llm-wiki"
  "Pratiyush/llm-wiki"
  "vercel-labs/knowledge-agent-template"
  "ivankuznetsov/llm-wiki"
  "ussumant/llm-wiki-compiler"
)
files=(AGENTS.md CLAUDE.md GEMINI.md README.md docs/getting-started.md)

manifest="$BASE/manifest.tsv"
printf "repo\tfile\tstatus\tpath\n" > "$manifest"

for repo in "${repos[@]}"; do
  owner="${repo%%/*}"
  name="${repo##*/}"
  target_dir="$BASE/${owner}__${name}"
  mkdir -p "$target_dir"
  for file in "${files[@]}"; do
    out="$target_dir/${file//\//__}"
    url="https://raw.githubusercontent.com/${repo}/main/${file}"
    status="ok"
    if ! curl -fsSL "$url" -o "$out"; then
      url="https://raw.githubusercontent.com/${repo}/master/${file}"
      if ! curl -fsSL "$url" -o "$out"; then
        rm -f "$out"
        status="missing"
      fi
    fi
    printf "%s\t%s\t%s\t%s\n" "$repo" "$file" "$status" "$out" >> "$manifest"
  done
done
