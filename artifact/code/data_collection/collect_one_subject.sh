#!/usr/bin/env bash
################################################################################
#
# Run the data-collection pipeline for a given subject.
#
# This script expects 2 positional arguments:
#   1) project_id -- Any of the (17) project IDs that are valid in Defects4J.
#   2) bug_id     -- 1, 2, 3, ... (must be valid for the given project_id).

# This script accepts an optional named arguments:
#   -h sshhosts -- A comma-separated series of hosts on which to run the mutation
#                  analysis, as well as the number of cores to use on each host. `:` is
#                  special syntax meaning localhost. For example, to run 20 parallel
#                  processes on the local machine and 10 on a machine named `other`,
#                  sshhosts would be `20/:,10/other`.
#
################################################################################

USAGE="usage: $0 [-h sshhosts] project_id bug_id"

# Change to the directory containing this script.
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR" || die "Could not change to directory $SCRIPT_DIR"

source customized-mutants.conf.sh

#
# Check arguments.
#
PASS=()
while getopts "h:" flag; do
  case "$flag" in
    h) PASS=(-h "$OPTARG");;
    \?) die "$USAGE";;
  esac
done

PID=${@:$OPTIND:1}
BID=${@:$OPTIND+1:1}

./10_mutation_analysis.sh "${PASS[@]}" "$PID" "$BID" || die "Mutation analysis failed"
./20_dmsg_analysis.sh "$PID" "$BID"                  || die "DMSG analysis failed"
./30_consolidate_data.sh "$PID" "$BID"               || die "Consolidation failed"

