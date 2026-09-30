#!/bin/sh
# Resume an M10 campaign in one Julia process so compilation is reused.
# Usage: m10_campaign.sh [118|300] OUTPUT [FIRST_INDEX] [LAST_INDEX|all] [SECONDS] [MAX_ITER]
set -eu

case_name=${1:-118}
output_root=${2:-"$(pwd)/m10_campaign"}
first_index=${3:-1}
last_index=${4:-all}
seconds=${5:-120}
max_iter=${6:-1000}

case "$case_name" in 118|300) ;; *) echo "case must be 118 or 300" >&2; exit 64 ;; esac
for value in "$first_index" "$seconds" "$max_iter"; do
    case "$value" in *[!0-9]*|'') echo "batch arguments must be positive integers" >&2; exit 64 ;; esac
    [ "$value" -gt 0 ] || { echo "batch arguments must be positive integers" >&2; exit 64; }
done
case "$last_index" in
    all) ;;
    *[!0-9]*|'') echo "last index must be a positive integer or all" >&2; exit 64 ;;
    *) [ "$last_index" -ge "$first_index" ] || { echo "first index exceeds last index" >&2; exit 64; } ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
mkdir -p "$output_root"
exec julia --project="$project_dir" "$script_dir/m10_contingency_campaign.jl" \
    "$case_name" "$output_root" "$first_index" "$last_index" "$seconds" "$max_iter"
