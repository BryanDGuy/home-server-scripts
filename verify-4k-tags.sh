#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the configuration file
source "$SCRIPT_DIR/server-config.cfg"

echo "Fetching all movies and tags from Radarr..."

# Create temporary files
tags_file=$(mktemp)
movies_file=$(mktemp)

# Fetch tags
curl -s -H "X-Api-Key: $API_KEY" "$RADARR_URL/api/v3/tag" > "$tags_file"
if [ $? -ne 0 ]; then
    echo "Failed to fetch tags"
    rm -f "$tags_file" "$movies_file"
    exit 1
fi

# Fetch all movies
curl -s -H "X-Api-Key: $API_KEY" "$RADARR_URL/api/v3/movie" > "$movies_file"
if [ $? -ne 0 ]; then
    echo "Failed to fetch movies"
    rm -f "$tags_file" "$movies_file"
    exit 1
fi

# Use Python to parse JSON and check tags
python3 << EOF
import json
import sys

with open('$tags_file', 'r') as f:
    tags = json.load(f)

with open('$movies_file', 'r') as f:
    movies = json.load(f)

# Find 4k tag ID
tag_4k_id = None
for tag in tags:
    if tag['label'] == '4k':
        tag_4k_id = tag['id']
        break

if tag_4k_id is None:
    print("Tag '4k' not found in Radarr instance.")
    sys.exit(1)

print(f"Found '4k' tag with ID: {tag_4k_id}")
print()
print("Checking movies...")
print("=" * 50)

missing_4k_tag = 0
extra_4k_tag = 0

for movie in movies:
    title = movie.get('title', 'Unknown')
    tags = movie.get('tags', [])
    has_4k_tag = tag_4k_id in tags

    # Check if movie has a file
    movie_file = movie.get('movieFile')
    if not movie_file:
        continue

    relative_path = movie_file.get('relativePath', '')

    # Check resolution from quality field
    quality_info = movie_file.get('quality', {}).get('quality', {})
    quality_resolution = quality_info.get('resolution', 0)

    # Also get mediaInfo resolution for display
    media_info = movie_file.get('mediaInfo', {})
    media_resolution = media_info.get('resolution', '')

    # Check for 4K: quality.resolution >= 2160
    is_4k = quality_resolution >= 2160

    # Use quality resolution for display, fall back to mediaInfo
    resolution = f"{quality_resolution}p" if quality_resolution > 0 else media_resolution

    # Check for mismatches
    if is_4k and not has_4k_tag:
        print(f"❌ MISSING TAG: {title}")
        print(f"   File: {relative_path}")
        print(f"   Resolution: {resolution if resolution else '(detected from filename)'}")
        print(f"   Issue: Is 4K but missing '4k' tag")
        print()
        missing_4k_tag += 1
    elif not is_4k and has_4k_tag:
        print(f"❌ EXTRA TAG: {title}")
        print(f"   File: {relative_path}")
        print(f"   Resolution: {resolution if resolution else 'Unknown'}")
        print(f"   Issue: Not 4K but has '4k' tag")
        print()
        extra_4k_tag += 1

print("=" * 50)
print("Summary:")
print(f"- Movies missing '4k' tag: {missing_4k_tag}")
print(f"- Movies with incorrect '4k' tag: {extra_4k_tag}")
print(f"- Total incorrect tags: {missing_4k_tag + extra_4k_tag}")

if missing_4k_tag == 0 and extra_4k_tag == 0:
    print()
    print("✓ All movies are correctly tagged!")

EOF

# Cleanup temporary files
rm -f "$tags_file" "$movies_file"
