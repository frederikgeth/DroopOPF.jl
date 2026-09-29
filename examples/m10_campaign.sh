#!/bin/sh
# Resume a numbered M10 campaign on an unconstrained workstation or CI runner.
# Usage: m10_campaign.sh [118|300] OUTPUT [BATCH_SIZE] [FIRST_BATCH] [LAST_BATCH] [SECONDS]
set -u

case_name=${1:-118}
output_root=${2:-"$(pwd)/m10_campaign"}
batch_size=${3:-1}
first_batch=${4:-1}
last_batch=${5:-1}
seconds=${6:-180}

case "$case_name" in 118|300) ;; *) echo "case must be 118 or 300" >&2; exit 64 ;; esac
for value in "$batch_size" "$first_batch" "$last_batch" "$seconds"; do
    case "$value" in *[!0-9]*|'') echo "batch arguments must be positive integers" >&2; exit 64 ;; esac
    [ "$value" -gt 0 ] || { echo "batch arguments must be positive integers" >&2; exit 64; }
done
[ "$first_batch" -le "$last_batch" ] || { echo "first batch exceeds last batch" >&2; exit 64; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$output_root"
campaign="$output_root/campaign.md"
printf '# M10 campaign\n\n- Case: %s\n- Batch size: %s\n- Requested batches: %s-%s\n- Per-batch end-to-end budget: %s seconds\n\n| Batch | Outcome directory | Supervisor exit |\n|---:|---|---:|\n' \
    "$case_name" "$batch_size" "$first_batch" "$last_batch" "$seconds" > "$campaign"

for batch in $(seq "$first_batch" "$last_batch"); do
    directory="$output_root/$(printf '%s-batch%03d' "$case_name" "$batch")"
    if [ -f "$directory/supervisor.md" ] && grep -q -- '- Outcome: completed' "$directory/supervisor.md"; then
        printf '| %s | %s | resumed: completed |\n' "$batch" "$directory" >> "$campaign"
        continue
    fi
    sh "$script_dir/m10_supervised_batch.sh" "$case_name" "$directory" \
        "$batch_size" "$batch" "$seconds"
    status=$?
    printf '| %s | %s | %s |\n' "$batch" "$directory" "$status" >> "$campaign"
done

printf '\nA nonzero supervisor exit is unresolved evidence and does not stop later batches.\n' >> "$campaign"
