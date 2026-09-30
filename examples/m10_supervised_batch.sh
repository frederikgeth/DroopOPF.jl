#!/bin/sh
# Run one M10 baseline batch under end-to-end wall-clock and CPU limits.
# Usage: m10_supervised_batch.sh [118|300] OUTPUT [BATCH_SIZE] [BATCH_NUMBER] [SECONDS]
set -u

case_name=${1:-118}
output=${2:-"$(pwd)/m10_contingency_baseline"}
batch_size=${3:-1}
batch_number=${4:-1}
seconds=${5:-180}

case "$case_name" in 118|300) ;; *) echo "case must be 118 or 300" >&2; exit 64 ;; esac
case "$batch_size" in *[!0-9]*|'') echo "batch size must be a positive integer" >&2; exit 64 ;; esac
case "$batch_number" in *[!0-9]*|'') echo "batch number must be a positive integer" >&2; exit 64 ;; esac
case "$seconds" in *[!0-9]*|'') echo "seconds must be a positive integer" >&2; exit 64 ;; esac
if [ "$batch_size" -eq 0 ] || [ "$batch_number" -eq 0 ] || [ "$seconds" -eq 0 ]; then
    echo "batch size, batch number, and seconds must be positive" >&2
    exit 64
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
mkdir -p "$output"
started=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
cat > "$output/supervisor.md" <<EOF
# M10 external supervisor

- Started: $started
- Case: $case_name
- Batch: $batch_number (size $batch_size)
- End-to-end wall-clock limit: $seconds seconds
- Child CPU limit: $seconds seconds
- Outcome: running

The child log is run.log. A supervisor timeout is unresolved, never safe.
EOF

(
    ulimit -t "$seconds"
    exec julia --project="$project_dir" -e '
        include(joinpath(dirname(Base.active_project()), "examples", "m10_contingency_baseline.jl"))
        name, output, size, number, limit = ARGS
        m10_contingency_baseline(name, output;
            batch_size=parse(Int, size), batch_number=parse(Int, number),
            base_max_cpu_time=parse(Float64, limit),
            scenario_max_cpu_time=parse(Float64, limit), max_iter=1000)
    ' "$case_name" "$output" "$batch_size" "$batch_number" "$seconds"
) > "$output/run.log" 2>&1 &
child=$!
deadline=$(( $(date +%s) + seconds ))
timed_out=false
while kill -0 "$child" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
        timed_out=true
        kill -TERM "$child" 2>/dev/null || true
        sleep 2
        kill -KILL "$child" 2>/dev/null || true
        break
    fi
    sleep 1
done
status=0
wait "$child" || status=$?
finished=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
outcome=completed
[ "$timed_out" = true ] && outcome=timed_out_unresolved
[ "$status" -ne 0 ] && [ "$timed_out" = false ] && outcome=child_failed_unresolved
[ "$status" -eq 152 ] && [ "$timed_out" = false ] && outcome=cpu_limited_unresolved
cat >> "$output/supervisor.md" <<EOF
- Finished: $finished
- Child exit status: $status
- Outcome: $outcome
EOF
printf '%s\n' "M10 supervisor outcome: $outcome (status $status)"
[ "$outcome" = completed ]
