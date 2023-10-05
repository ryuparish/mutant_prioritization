#!/usr/bin/env bash
################################################################################
#
# This script computes and exports a subsumption graph for each top-level class
# of a given subject. It also combines all subsumption graphs into a single
# file (CM_RESULTS_ROOT/PID/BID/dmsgs.csv)
#
# This script expects 2 positional arguments:
#   1) project_id -- Any of the (17) project IDs that are valid in Defects4J.
#   2) bug_id     -- 1, 2, 3, ... (must be valid for the given project_id).
#
# This script expects the following files (normally produced by 10_mutation_analysis.sh) to exist:
#   "$CM_RESULTS_ROOT/<PID>/<BID>/mutants.log" 
#   "$CM_RESULTS_ROOT/<PID>/<BID>/killMap.csv" 
#   "$CM_RESULTS_ROOT/<PID>/<BID>/covMap.csv" 
#   "$CM_RESULTS_ROOT/<PID>/<BID>/testMap.csv" 
#
# ($CM_RESULTS_ROOT is defined in customized-mutants.conf.sh.)
#
# NOTE: subsumption.jar must exist in the utils directory.
#
################################################################################
# Set up environment
source customized-mutants.conf.sh

# Check arguments
[ $# -eq 2 ] || die "usage: $0 project_id bug_id"
PID="$1"
BID="$2"

declare -r VID="${BID}f"
declare -r RESULTS_DIR="$CM_RESULTS_ROOT/$PID/$VID"

# Create the expanded score matrix (MuJava format) and write it to:
# $CM_RESULTS_ROOT/<project_id>/<bug_id>/scoreMatrix.csv

# Make sure that Major's data files exist for at least the developer tests.
[ -e "$RESULTS_DIR/mutants.log" ] || die "Mutant data not found in: $RESULTS_DIR"

declare -r score_matrix="$RESULTS_DIR/scoreMatrix.csv"

# Expand the mutant list and kill map into a full score matrix
java -cp utils/subsumption.jar -Xmx5G majorFiles.MajorMultipleFileConverter \
  -m "$RESULTS_DIR/mutants.log" \
  -k "$RESULTS_DIR/killMap.csv" \
  -c "$RESULTS_DIR/covMap.csv" \
  -t "$RESULTS_DIR/testMap.csv" \
  -o "$score_matrix"

log_custmut "Score matrix successfully created: ${score_matrix}"

log_custmut "Building mapping from mutant id to mutation target"
declare -r mutant_map="$RESULTS_DIR/mutant_class.map"
echo "Mutant:Target:Line" > $mutant_map
# Format of mutants.log (note the missing header and ':' separator):
# mutant id:mutation operator:from:to:mutation target:line number:details
# (the mutation target is a fully qualified class name plus an optional inner
# class and/or method signature. We extract the full target name here;
# the slicing script controls how these targets are broken down (e.g., method,
# or top-level class).
cut -f1,5,6 -d":" "$RESULTS_DIR/mutants.log" >> $mutant_map

log_custmut "Slicing score matrix by mutation target"
declare -r slices_dir="$RESULTS_DIR/score_matrix_slices"
rm -rf "$slices_dir" && mkdir -p "$slices_dir"
Rscript ./utils/slice_score_matrix.R "$score_matrix" "$mutant_map" "$slices_dir"

# Verify that the union of all score matrix slices is identical to the original
# score matrix.
orig=$(mktemp)
union=$(mktemp)
tail -n+2 $score_matrix | sort > $orig
for file in $slices_dir/*/scoreMatrix.csv; do tail -n+2 $file; done | sort > $union
cmp $orig $union

log_custmut "Generating and visualizing subsumption data"
for class_dir in "$slices_dir"/*; do
  printf "$class_dir ... "
  java -Xmx8G -cp utils/subsumption.jar dynamic.MutantAnalyzer \
    -i "$class_dir/scoreMatrix.csv" \
    -l -m -dot -ngn -as -sc SNn -cs
done

log_custmut "Consolidating subsumption data"
declare -r dmsgs_csv="$RESULTS_DIR/dmsgs.csv"
Rscript ./utils/join_dmsgs.R "$PID" "$BID" "$slices_dir" "$dmsgs_csv"
log_custmut "DMSGs successfully created: $dmsgs_csv"
