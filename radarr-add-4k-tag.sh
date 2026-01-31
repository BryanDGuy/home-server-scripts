#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the configuration file
source "$SCRIPT_DIR/server-config.cfg"

get_tag_id() {
    local response=$(curl -s -w "\n%{http_code}" \
        -H "X-Api-Key: $API_KEY" \
        "$RADARR_URL/api/v3/tag")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" -eq 200 ]; then
        # Extract tag ID for "4k" label using grep and sed (remove whitespace first)
        tag_id=$(echo "$body" | tr -d '\n' | tr -d ' ' | grep -o '"label":"4k","id":[0-9]*' | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
        echo "$tag_id"
    else
        echo ""
    fi
}

add_tag() {
    local movie_id="$1"
    local tag_id="$2"

    local payload="{\"movieIds\":[$movie_id],\"tags\":[$tag_id],\"applyTags\":\"add\"}"

    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$RADARR_URL/api/v3/movie/editor")

    if [ "$http_code" -eq 202 ]; then
        echo "Tag added successfully."
        return 0
    else
        echo "Failed to add tag. HTTP Status Code: $http_code"
        exit 1
    fi
}

remove_tag() {
    local movie_id="$1"
    local tag_id="$2"

    local payload="{\"movieIds\":[$movie_id],\"tags\":[$tag_id],\"applyTags\":\"remove\"}"

    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT \
        -H "X-Api-Key: $API_KEY" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$RADARR_URL/api/v3/movie/editor")

    if [ "$http_code" -eq 202 ]; then
        echo "Tag removed successfully."
        return 0
    else
        echo "Failed to remove tag. HTTP Status Code: $http_code"
        exit 1
    fi
}

get_movie_tags() {
    local movie_id="$1"
    local response=$(curl -s -w "\n%{http_code}" \
        -H "X-Api-Key: $API_KEY" \
        "$RADARR_URL/api/v3/movie/$movie_id")

    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" -eq 200 ]; then
        # Extract tags array using grep and sed (remove whitespace first)
        tags=$(echo "$body" | tr -d '\n' | tr -d ' ' | grep -o '"tags":\[[^]]*\]' | sed 's/"tags":\[//; s/\]//; s/,/ /g')
        echo "$tags"
    else
        echo ""
    fi
}

check_is_4k() {
    local movie_id="$1"

    # Fetch movie details to get quality info
    local response=$(curl -s -H "X-Api-Key: $API_KEY" "$RADARR_URL/api/v3/movie/$movie_id")

    # Extract resolution from quality.quality.resolution (integer field)
    local quality_resolution=$(echo "$response" | grep -o '"quality":{[^}]*"resolution":[0-9]*' | grep -o '"resolution":[0-9]*' | grep -o '[0-9]*' | head -1)

    # Check if resolution is 2160 or higher (4K)
    if [ -n "$quality_resolution" ] && [ "$quality_resolution" -ge 2160 ]; then
        return 0
    else
        return 1
    fi
}

main() {
    local movie_id="${radarr_movie_id}"
    local movie_filename="${radarr_moviefile_relativepath}"
    local event_type="${radarr_eventtype}"

    echo "Executing add 4k tag script..."

    if [ "$event_type" = "Test" ]; then
        echo "Script is running in test mode. Do nothing."
        exit 0
    fi

    local tag_id=$(get_tag_id)

    if [ -z "$tag_id" ]; then
        echo "Tag '4k' not found in Radarr instance."
        exit 1
    fi

    local tags=$(get_movie_tags "$movie_id")
    local has_tag=false

    if echo " $tags " | grep -q " ${tag_id} "; then
        has_tag=true
    fi

    if [ "$has_tag" = true ]; then
        if ! check_is_4k "$movie_id"; then
            remove_tag "$movie_id" "$tag_id"
            echo "Removed '4k' tag from the movie."
        else
            echo "Movie already marked as 4k. No action taken."
        fi
    else
        if check_is_4k "$movie_id"; then
            add_tag "$movie_id" "$tag_id"
            echo "Added '4k' tag to the movie."
        else
            echo "Movie not marked as 4k. No action taken."
        fi
    fi
}

main
