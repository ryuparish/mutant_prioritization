#!/usr/bin/env bash
################################################################################
#
# This script consolidates all data, for a given subject, into one data file:
# CM_RESULTS_ROOT/PID/BID/mutant_context_data.csv
#
# This script expects 2 positional arguments:
#   1) project_id -- Any of the (17) project IDs that are valid in Defects4J.
#   2) bug_id     -- 1, 2, 3, ... (must be valid for the given project_id).
#
# It expects the following files to exist on the filesystem (normally produced by
# preceding steps in the pipeline):
#   "$CM_RESULTS_ROOT/<PID>/<BID>/dmsgs.csv" 
#   "$CM_RESULTS_ROOT/<PID>/<BID>/killMap.csv" 
#   "$CM_RESULTS_ROOT/<PID>/<BID>/mutants.log" 
#   "$CM_RESULTS_ROOT/<PID>/<BID>/mutants.context" 
#   "$CM_RESULTS_ROOT/<PID>/<BID>/scoreMatrix.csv" 
#
# NOTE: subsumption.jar must exist in the utils directory.
#
################################################################################
# Set up environment
source customized-mutants.conf.sh

# Check arguments
[ $# -ge 2 ] || die "usage: $0 project_id bug_id"
PID=$1
BID=$2

declare -r VID="${BID}f"
declare -r RESULTS_DIR="$CM_RESULTS_ROOT/$PID/$VID"

# The input directories and files
declare -r DMSGS_FILE="$RESULTS_DIR/dmsgs.csv"
declare -r KILLMAP_FILE="$RESULTS_DIR/killMap.csv"
declare -r MUT_LOG_FILE="$RESULTS_DIR/mutants.log"
declare -r MUT_CONTEXT_FILE="$RESULTS_DIR/mutants.context"
declare -r SCORE_MATRIX_FILE="$RESULTS_DIR/scoreMatrix.csv"

# Make sure that all required inputs exist
for file in "$MUT_LOG_FILE" "$MUT_CONTEXT_FILE" "$SCORE_MATRIX_FILE" "$DMSGS_FILE"; do
  [ -e "$file" ] || die "Missing data file: $file"
done

# The final output file for the given subject
declare -r OUT_FILE="$RESULTS_DIR/customized-mutants.csv"

echo "Consolidating data files for: $PID-$BID"

# Gather the triggering tests for the subject 
tests_trigger_tmp_path=$(mktemp)
declare -r tests_trigger_tmp_path
grep "\---" "$D4J_HOME/framework/projects/$PID/trigger_tests/$BID" > "$tests_trigger_tmp_path"

# Define a regex to filter tests for triviality. Because the EvoSuite tests
# are sometimes written strangely with respect to catching exceptions, we
# can't rely on them to accurately reflect trivial mutants. Thus, we base
# our triviality classification only on tests that are not written by
# EvoSuite. Since EvoSuite tests all contain the string "_ESTest", any
# test that doesn't contain "_ESTest" can be used for triviality.
TRIVIALITY_REGEX="^((?!_ESTest).)*\$"

declare -r tmp_file=$(mktemp)

if java -cp utils/subsumption.jar majorFiles.ContextBuilderMain \
        -p   "$PID" -b "$BID" \
        -mf  "$DMSGS_FILE" \
        -cf  "$MUT_CONTEXT_FILE" \
        -sf  "$SCORE_MATRIX_FILE" \
        -ttr "$TRIVIALITY_REGEX" \
        -lf  "$MUT_LOG_FILE" \
        -ttf "$tests_trigger_tmp_path" \
        -o   "$tmp_file"; then
  log_custmut "Successfully exported context data file: $tmp_file"
else
  die "Could not consolidate data files"
fi

Rscript utils/add_features_labels.R "$DMSGS_FILE" "$KILLMAP_FILE" "$tmp_file" "$OUT_FILE"

log_custmut "Successfully created consolidated data file: $OUT_FILE"
