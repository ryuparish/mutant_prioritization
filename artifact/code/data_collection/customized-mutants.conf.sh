#!/usr/bin/env bash
#
# Configuration file for data-collection scripts. Adapt the exported environment
# variables if your directory layout differs from the following default:
#
# (CM_DATA_HOME)
#     |
#     |-- data_analysis (CM_ANALYSIS)
#     |
#     |
#     |-- data_collection (CM_COLLECTION)
#     |    |
#     |    |-- utils (CM_UTILS)
#     |
#     |
#     |-- deps
#     |    |
#     |    |-- defects4j (D4J_HOME) [v2.0.0]
#     |    |
#     |    |-- major (MAJOR_HOME)   [v2.0.0]
#     |
#     |
#     |-- mutant_data (CM_MUTANT_DATA)
#     |

# General flags for all bash scripts
set -o nounset
set -o errexit

# Set current directory as CWD and export it
CM_COLLECTION=$(pwd)

# Workaround for Cygwin/MinGW: use relative path on non-unix machines
case "$(uname -s)" in
    Darwin)
        echo 'Detected OS: Mac OS X' >&2
        CM_DATA_HOME=$(cd .. && pwd)
    ;;

    Linux)
        echo 'Detected OS: Linux' >&2
        CM_DATA_HOME=$(cd .. && pwd)
    ;;

    CYGWIN*|MINGW32*|MSYS*)
        echo 'Detected OS: Windows' >&2
        CM_DATA_HOME="../"
    ;;

    *)
        echo 'Detected OS: Unknown' >&2
        exit 1
    ;;
esac

# Set up environment
export CM_DATA_HOME
export CM_COLLECTION

export D4J_HOME="$CM_DATA_HOME/deps/defects4j"
export MAJOR_HOME="$CM_DATA_HOME/deps/major"
export GNU_PARALLEL_HOME="$CM_DATA_HOME/deps/parallel"

export CM_RESULTS_ROOT="$CM_DATA_HOME/results"
export CM_DATA="$CM_DATA_HOME/data"
export CM_MUTANT_DATA="$CM_DATA_HOME/mutant_data"
export CM_ANALYSIS="$CM_DATA_HOME/data_analysis"
export CM_UTILS="$CM_COLLECTION/utils"
export CM_BUILD_XML="$CM_COLLECTION/defects4j.build.xml"
export CM_GEN_TESTS="$CM_DATA_HOME/tests/gen_tests"
export CM_ADD_TESTS="$CM_DATA_HOME/tests/add_tests"

# Set the commands for defects4j and ant
export D4J_CMD="$D4J_HOME/framework/bin/defects4j"
export ANT_CMD="$MAJOR_HOME/bin/ant"

# Prepend PATH with utils, Major's executables, and GNU Parallel.
# Make sure to put utils first: we rely on D4J to call an executable named
# "major", which has to be on the PATH (and exists in D4J).
export PATH=$CM_UTILS:$MAJOR_HOME/bin:$GNU_PARALLEL_HOME/bin:$PATH

################################################################################
# Helper subroutines

# Print error message and exit
die() {
    echo "$1" >&2
    exit 1
}

# Determines and returns the path for the kill matrix.
# Expects two to four arguments:
# 1) project_id (PID)
# 2) bug_id (BID)
# optional:
# 3) test_suite_id (TID)
# 4) additional (any String is interpreted as yes)
get_kill_matrix_dir() {
    local PID=$1
    local BID=$2
    local TID="${3:-}"
    local ADL="${4:-}"

    [ -z "$TID" ] || die "Support for TID tests removed"
    [ -z "$ADL" ] || die "Support for ADL tests removed"
    echo "$CM_MUTANT_DATA/$PID/$BID/killmatrix"
}

# Determines and returns the path for the score matrix.
# Expects two to four arguments:
# 1) project_id (PID)
# 2) bug_id (BID)
# optional:
# 3) test_suite_id (TID)
# 4) additional (any String is interpreted as yes)
get_score_matrix_dir() {
    local PID="$1"
    local BID="$2"
    local TID="${3:-}"
    local ADL="${4:-}"

    [ -z "$TID" ] || die "Support for TID tests removed"
    [ -z "$ADL" ] || die "Support for ADL tests removed"
    echo "$CM_MUTANT_DATA/$PID/$BID/subsumption"
}

# Determines and returns the path for the consolidated data file.
# Expects two to four arguments:
# 1) project_id (PID)
# 2) bug_id (BID)
# optional:
# 3) test_suite_id (TID)
# 4) additional (any String is interpreted as yes)
get_data_dir() {
    local PID=$1
    local BID=$2
    local TID="${3:-}"
    local ADL="${4:-}"

    [ -z "$TID" ] || die "Support for TID tests removed"
    [ -z "$ADL" ] || die "Support for ADL tests removed"
    echo "$CM_MUTANT_DATA/$PID/$BID/data"
}

# Check whether the working directory exists and is valid; set project id (PID)
# and bug id (BID)
check_work_dir() {
    local work_dir="$1"
    local CONFIG="$work_dir/.defects4j.config"
    [ -e "$CONFIG" ] || die "Invalid working directory: $work_dir"
    PID=$(grep "pid=" $CONFIG | perl -ne 's/pid=(.+)/$1/; print')
    BID=$(grep "vid=" $CONFIG | perl -ne 's/vid=(\d+)f/$1/; print')
}

# Check whether the expanded score matrix exists for a particular subject.
# Returns 0 if the file exists, 1 otherwise.
# Expects two to four arguments:
# 1) project_id (PID)
# 2) bug_id (BID)
# optional:
# 3) test_suite_id (TID)
# 4) additional (any String is interpreted as yes)
check_score_matrix() {
    if [ -e "$CM_MUTANT_DATA/$1/$2/subsumption/scoreMatrix.csv" ]; then
        return 0
    else
        return 1
    fi
}

# Check whether the subsumption data files exist for a particular subject.
# Returns 0 if the data files exist, 1 otherwise.
# Expects two to four arguments:
# 1) project_id (PID)
# 2) bug_id (BID)
# optional:
# 3) test_suite_id (TID)
# 4) additional (any String is interpreted as yes)
check_subsumption_results() {
    local dir="$(get_score_matrix_dir "$1" "$2" ${3:-} ${4:-})"
    if [ -e "$dir/run0/mutants_test0.csv" ]; then
        return 0
    else
        return 1
    fi
}

# Prepend CUSTMUT to messages sent to STDOUT
log_custmut() {
  local MSG=$1
  echo "[CUSTMUT] $MSG"
}

