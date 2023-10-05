#!/usr/bin/env bash
#
# Run the data-collection pipeline for each subject in subjects.csv and create
# the customized-mutants.csv data file.

# This script expects to be run from its containing directory (data_collection).
cd "$(dirname "$0")" || exit 200

source customized-mutants.conf.sh

tail -n+2 subjects.csv | while IFS="" read -r line; do
  pid=$(echo "$line" | cut -f1 -d',')
  bid=$(echo "$line" | cut -f2 -d',')
  log_custmut "Processing $pid-$bid"
  ./collect_one_subject.sh "$@" "$pid" "$bid"
done

log_custmut "Creating consolidated customized-mutants.csv"
final_custmut_csv="$CM_RESULTS_ROOT/customized-mutants.csv"
declare -r final_custmut_csv
rm -f "$final_custmut_csv"
find "$CM_RESULTS_ROOT"/*/ -name "customized-mutants.csv" -print0 -quit | xargs -0 head -n 1 > "$final_custmut_csv"
find "$CM_RESULTS_ROOT"/*/ -name "customized-mutants.csv" -print0 | xargs -0 tail -q -n +2 >> "$final_custmut_csv"
log_custmut "Successfully compiled $final_custmut_csv"
