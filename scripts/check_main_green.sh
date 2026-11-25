#!/usr/bin/env bash
# Stops unless the checked-out commit is the tip of main and ci.yml passed on it. The upload
# workflows run this before building anything.
set -euo pipefail
repo=${GITHUB_REPOSITORY:-aytutuna/LazyScan}
sha=$(git rev-parse HEAD)
tip=$(gh api "repos/$repo/commits/main" --jq .sha)
if [ "$tip" != "$sha" ]; then
  echo "Not uploading: $sha is not the tip of main ($tip)."
  exit 1
fi
passed=$(gh run list --repo "$repo" --workflow ci.yml --commit "$sha" --status success --json databaseId --jq length)
if [ "$passed" -lt 1 ]; then
  echo "Not uploading: no passing ci.yml run on $sha."
  exit 1
fi
echo "$sha is the tip of main and its tests passed."
