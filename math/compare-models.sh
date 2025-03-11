#!/usr/bin/env bash
set -Eeuo pipefail

# Number of lines per chunk
CHUNK_LINES=100

MODEL_COMMAND_1=("ollama" "run" "vanilj/phi-4")
MODEL_COMMAND_2=("ollama" "run" "vanilj/phi-4-unsloth:q8_0")

PROGRESS_FILE="progress.log"
OVERVIEW_FILE="overview.txt"

main_dir="$(pwd)"
touch "$main_dir/$PROGRESS_FILE"
touch "$main_dir/$OVERVIEW_FILE"

log() {
  local message="[${USER:-$(whoami)}@$(hostname)] [$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$message"
  echo "$message" >> "$main_dir/$PROGRESS_FILE"
}

is_processed() {
  local file_path="$1"
  grep -Fxq "$file_path" "$main_dir/$PROGRESS_FILE"
}

mark_processed() {
  local file_path="$1"
  echo "$file_path" >> "$main_dir/$PROGRESS_FILE"
}

log "Script started."

process_files_in_directory() {
  local dir="$1"
  log "Processing directory: $dir"

  shopt -s nullglob
  local all_files=("$dir"/*.txt)
  shopt -u nullglob

  [[ ${#all_files[@]} -eq 0 ]] && {
    log "No files found in $dir"
    return
  }

  for file in "${all_files[@]}"; do
    [[ -f "$file" && ! -L "$file" ]] || continue

    if is_processed "$file"; then
      log "Skipping (already processed): $file"
      continue
    fi

    log "Processing file: $file"

    local file_name="$(basename "$file")"
    local sanitized_name
    sanitized_name="$(echo "$file_name" | tr -d '[:space:]')"
    local temp_dir
    temp_dir="$(mktemp -d "$dir/tmp_${sanitized_name}_XXXXXX")"
    log "Created temporary directory: $temp_dir"

    local preprocessed_file="$temp_dir/preprocessed.txt"
    head -n $CHUNK_LINES "$file" > "$preprocessed_file"
    log "Truncated $file to the first $CHUNK_LINES lines."

    # Summarize with first model
    log "Summarizing file with vanilj/phi-4: $file"
    {
      echo "\n--- Summary from vanilj/phi-4 for: $file_name ---"
      echo "Summarize the following text, focusing on main ideas."
      cat "$preprocessed_file"
    } | "${MODEL_COMMAND_1[@]}" 2>>"$main_dir/$PROGRESS_FILE" | tee -a "$main_dir/$OVERVIEW_FILE"

    # Summarize with second model
    log "Summarizing file with vanilj/phi-4-unsloth:q8_0: $file"
    {
      echo "\n--- Summary from vanilj/phi-4-unsloth:q8_0 for: $file_name ---"
      echo "Summarize the following text, focusing on main ideas."
      cat "$preprocessed_file"
    } | "${MODEL_COMMAND_2[@]}" 2>>"$main_dir/$PROGRESS_FILE" | tee -a "$main_dir/$OVERVIEW_FILE"

    mark_processed "$file"
    log "Marked $file as processed."

    rm -rf "$temp_dir"
    log "Removed temporary directory: $temp_dir"
  done
}

process_files_in_directory "$main_dir"

log "Script completed."

