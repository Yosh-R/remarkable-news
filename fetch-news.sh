#!/usr/bin/env bash
#
# fetch-news.sh
#
# Reads publications from recipes.txt, builds a dated EPUB for each one
# using Calibre's news fetcher, and uploads the result to the /News
# folder of the reMarkable cloud via rmapi.
#
# Per-recipe failures are logged but do not abort the run. The script
# exits non-zero only if every recipe fails — that way one publication
# being temporarily broken does not mark the whole workflow as failed.

# Note: deliberately NOT using `set -e`. We want to continue past
# individual recipe failures.
set -uo pipefail

RECIPES_FILE="${RECIPES_FILE:-recipes.txt}"
REMOTE_DIR="/News"
DATE_STAMP="$(date -u +%Y-%m-%d)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ ! -f "$RECIPES_FILE" ]]; then
    echo "Error: recipes file '$RECIPES_FILE' not found" >&2
    exit 1
fi

successes=()
failures=()

# Each non-empty, non-comment line in recipes.txt is one publication.
# Format:  <recipe-filename>  <display name>
#   first whitespace-delimited token is the .recipe filename in
#   Calibre's repo (without the .recipe extension); the remainder of
#   the line is the human-friendly title used in the EPUB filename.
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    # Strip comments (anything from # onward) and surrounding whitespace.
    line="${raw_line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue

    # Split into recipe slug and display name. If no display name is
    # given, fall back to the slug.
    recipe_slug="${line%% *}"
    if [[ "$line" == *" "* ]]; then
        display_name="${line#* }"
    else
        display_name="$recipe_slug"
    fi

    recipe_url="https://raw.githubusercontent.com/kovidgoyal/calibre/master/recipes/${recipe_slug}.recipe"
    recipe_file="$WORK_DIR/${recipe_slug}.recipe"
    output_file="$WORK_DIR/${display_name} - ${DATE_STAMP}.epub"

    echo "::group::Processing ${display_name} (${recipe_slug})"

    # Download the recipe fresh each run. This way we don't depend on
    # which Calibre version the runner shipped with — we always get the
    # current upstream recipe, which matters when sites change layout.
    if ! curl -fsSL -o "$recipe_file" "$recipe_url"; then
        echo "Failed to download recipe from $recipe_url" >&2
        failures+=("$display_name (recipe download)")
        echo "::endgroup::"
        continue
    fi

    # --output-profile=tablet picks reasonable defaults for e-reader
    # sized screens (font size, image rescaling, margins).
    if ! ebook-convert "$recipe_file" "$output_file" \
            --output-profile=tablet; then
        echo "Calibre failed to build EPUB for $display_name" >&2
        failures+=("$display_name (build)")
        echo "::endgroup::"
        continue
    fi

    if [[ ! -s "$output_file" ]]; then
        echo "Calibre produced an empty file for $display_name" >&2
        failures+=("$display_name (empty output)")
        echo "::endgroup::"
        continue
    fi

    if ! rmapi put "$output_file" "$REMOTE_DIR/"; then
        echo "rmapi failed to upload $output_file" >&2
        failures+=("$display_name (upload)")
        echo "::endgroup::"
        continue
    fi

    successes+=("$display_name")
    echo "::endgroup::"
done < "$RECIPES_FILE"

echo
echo "===== Summary ====="
echo "Successes (${#successes[@]}):"
for s in "${successes[@]}"; do echo "  ✓ $s"; done
echo "Failures  (${#failures[@]}):"
for f in "${failures[@]}"; do echo "  ✗ $f"; done

# Non-zero exit only if EVERY recipe failed.
if [[ ${#successes[@]} -eq 0 ]]; then
    exit 1
fi
