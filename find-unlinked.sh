#!/bin/bash

# Usage: find-unlinked.sh <SOURCE> <DEST> <EXTENSIONS>
# EXTENSIONS should be comma-separated (e.g., "mkv,mp4,avi")

if [ $# -ne 3 ]; then
    echo "Usage: $0 <SOURCE> <DEST> <EXTENSIONS>"
    echo "Example: $0 /source/path /dest/path mkv,mp4,avi"
    exit 1
fi

SOURCE="$1"
DEST="$2"
IFS=',' read -ra EXTENSIONS <<< "$3"

# Build find command with extensions
extensions_args=()
for i in "${!EXTENSIONS[@]}"; do
    if [ $i -eq 0 ]; then
        extensions_args+=(-name "*.${EXTENSIONS[$i]}")
    else
        extensions_args+=(-o -name "*.${EXTENSIONS[$i]}")
    fi
done

total_size=0

while read -r file; do
    inode=$(stat -c '%i' "$file")
    
    if ! find "$DEST" -type f -inum "$inode" -print -quit | grep -q .; then
        size=$(stat -c '%s' "$file")
        total_size=$((total_size + size))
        
        dir=$(dirname "$file")
        output+="${dir#$SOURCE/}"$'\n'
    fi
done < <(find "$SOURCE" -type f \( "${extensions_args[@]}" \))

echo "$output" | uniq
echo "Total Size: $(numfmt --to=iec-i --suffix=B $total_size)"