#!/usr/bin/env bash
################################################################################
#
# Parallelized kill matrix computation for all classes of a Defects4J project version.
#
# Given a project_id and bug_id, this script:
#   1. checks out the fixed project version
#   2. mutates all classes, and
#   3. computes a full kill matrix.
#
# This script expects 2 positional arguments:
#   1) project_id -- Any of the (17) project IDs that are valid in Defects4J.
#   2) bug_id     -- 1, 2, 3, ... (must be valid for the given project_id).
#
# This script accepts two optional named arguments:
#   -m mml_file -- path to a compiled mml file (the default is all-mutants.mml.bin in this directory).
#   -h sshhosts -- A comma-separated series of hosts on which to run this analysis and the number of
#                  cores to use on each host. `:` is special syntax meaning localhost. For example,
#                  to run 20 parallel processes on the local machine and 10 on a machine named
#                  `other`, sshhosts would be `20/:,10/other`.
#
# When this scripts completes, it will have added to results/<PID>/<BID>/ the following
# files:
#   killMap.csv    -- The kill matrix. Associates tests with mutants that kill them.
#                     (Also indicates failures and timeouts.)
#   testMap.csv    -- Mapping between test IDs and names, as well as execution runtimes.
#   covMap.csv     -- Associates test with mutants covering them.
#   mutants.log    -- Descriptions of each mutant produced during mutation analysis.
#
# Additionally, files that might be useful for debugging:
#   antOutput.log  -- The stdout and stderr of mutation testing for a particular job
#                     (batch of mutants).
#   summary.csv
#
################################################################################
# Set up environment
source customized-mutants.conf.sh

if ! command -v svn &> /dev/null
then
    >&2 echo "svn could not be found; please install Subversion and try again"
    exit 100
fi

# Make sure GNU coreutils are available
realpath --version 2>&1 | grep -q "realpath (GNU coreutils)" || die "realpath not available; please install GNU coreutils."

# Make sure GNU parallel is available
parallel --version >/dev/null 2>&1 || die "parallel not available; please run ./init.sh"

USAGE="usage: $0 [-h sshhosts] [-m mml_file] [project_id bug_id]"

SSHHOSTS=":"
MML_FILE="$CM_COLLECTION/all-mutants.mml.bin"
while getopts ":h:m:" flag; do
  case "$flag" in
    h) SSHHOSTS="$OPTARG";;
    m) MML="$OPTARG";;
    \?) die "Unknown flag $flag -- $USAGE";;
  esac
done


# Check whether MML file exists and get its absolute path
[ -e "$MML_FILE" ] || die "MML file does not exist: $MML_FILE"
MML=$(realpath -e "$MML_FILE")
# The export MML variable is picked up by the 'major' wrapper (utils subdirectory).
export MML

# Shift away args parsed by getopts
shift $((OPTIND - 1))

log_custmut "Use MML file: ${MML}"

# Check for the two required arguments
[ $# -ge 2 ] || die "$USAGE"

declare -r PID="$1"
declare -r BID="$2"
declare -r VID="${BID}f"

mkdir -p "$CM_RESULTS_ROOT"


CWD=$(pwd)

# Set working directory for checked-out project version and set a root
# "jobs" directory for which will contain unique subdirectories for each
# parallel worker.
#
# BSD and GNU mktemp differ: -t in the GNU version expects the Xs in the
# template as placeholders and replaces them with a random sequence, whereas -t
# in the BSD version simply uses the argument as template prefix (the Xs remain
# part of the name).
#
# These directories will be unique on the local machine. However, the paths
# will also be used on remote machines (if -h is given). While unlikely, it
# is possible those paths will already exist on these worker hosts.
WORK_DIR=$(mktemp -d -t "CM-$PID-$VID.XXXXXXXX")
[ -d "$WORK_DIR" ] || die "Cannot create temporary directory"

JOBS_DIR=$(mktemp -d -t "CM-$PID-$VID-jobs.XXXXXXXX")
[ -d "$JOBS_DIR" ] || die "Cannot create jobs directory"

log_custmut "Working directory: $WORK_DIR"
log_custmut "Jobs directory: $JOBS_DIR"

# The log file for the entire analysis (incl. output of individual jobs).
mkdir -p "$CM_RESULTS_ROOT/$PID/$VID"
declare -r LOG_FILE="$CM_RESULTS_ROOT/$PID/$VID/log"
# Clear the log file, if it exists.
true >"$LOG_FILE"

log_custmut "Detailed log file: $LOG_FILE"

# Checkout the project version
log_custmut "Checkout project version: $PID-$VID to $WORK_DIR"
"$D4J_CMD" checkout -p "$PID" -v "$VID" -w "$WORK_DIR"

# Compile sources and tests
log_custmut "Compile sources and tests in $WORK_DIR"
"$D4J_CMD" compile -w "$WORK_DIR"

# Generate all mutants
log_custmut "Generate mutants in $WORK_DIR"
"$ANT_CMD" \
   -f "$CM_COLLECTION/defects4j.build.xml" \
   "-Dbasedir=$WORK_DIR" \
   "-Dd4j.home=$D4J_HOME" \
   mutate >> "$LOG_FILE" 2>&1

# Preprocessing only: collect coverage information and test map
log_custmut "Run preprocessing in $WORK_DIR"
cd "$WORK_DIR"
"$ANT_CMD" \
   -f "$CM_BUILD_XML" \
   "-Dbasedir=$WORK_DIR" \
   "-Dd4j.home=$D4J_HOME" \
   -Dmajor.analysisType=preproc \
   -Dmajor.haltOnFailure=false \
   mutation.test >> "$LOG_FILE" 2>&1

# Determine and shuffle the set of covered mutants from covMap.csv
log_custmut "Determine the set of covered mutants, using $WORK_DIR/covMap.csv"
# (covMap.csv format: TestNo,MutantNo)
[ -e "covMap.csv" ] || die "Coverage map ($WORK_DIR/covMap.csv) not found"
tail -n+2 "$WORK_DIR/covMap.csv" | cut -f2 -d',' | sort -u | shuf > "$WORK_DIR/includeMutants.txt"
N_MUT=$(wc -l < "$WORK_DIR/includeMutants.txt")

# Run kill-matrix computation in parallel
# Number of mutant IDs to be processed by each job
N_IDS=10
mkdir mutantBatches 
pushd mutantBatches
split -a5 -l${N_IDS} "$WORK_DIR/includeMutants.txt" "batch-"
popd

# Make sure each job JVM scales its number of threads, based on the number of "available" CPUs.
# (Other related options: -XX:CICompilerCount=2 -XX:ParallelGCThreads=2 -XX:ConcGCThreads=2)
export JAVA_TOOL_OPTIONS="-XX:ActiveProcessorCount=4 ${JAVA_TOOL_OPTIONS:-} ${_JAVA_OPTIONS:-}"

extract_batch_id() {
  local -r f="$1"
  if [[ $f =~ ^mutantBatches/batch-(.*)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    die "Should have matched mutantsBatch regex: $f" 
  fi
}

# Create jobs file. Each job will process a batch of mutants produced
# in the last step.
log_custmut "Analyze $N_MUT mutants, $N_IDS mutants per job"
# Prep the directories for each job/batch in $JOBS_DIR. This is done locally first
# rather than directly into the worker filesystem for 2 reasons. First, this has to
# be done locally for some jobs since they will be executed on this machine. Second,
# it simplifies the --transferfile logic substantially. This is extra work for the
# filesystem/network, but that extra work is still negligible next to the overall
# cost of this script.
log_custmut "Preparing jobs directory locally"
declare -a batch_ids=()
for f in mutantBatches/batch-*; do
  batch_id=$(extract_batch_id "$f")
  batch_ids+=("$batch_id")
  mkdir -p "$JOBS_DIR/$batch_id"
  cp "$f" "$JOBS_DIR/$batch_id/batchMutantIDs.txt"
done

# Run mutation analysis in parallel.
#
# The call to rsync is wrapped in a timeout call to work around an odd case where
# it'll sometimes hang permanently.
log_custmut "Running jobs in parallel"
parallel --progress                                              \
  --joblog "$CM_RESULTS_ROOT/$PID/$VID/joblog"                   \
  --retries 10                                                   \
  --env JAVA_TOOL_OPTIONS --env MML                              \
  --controlmaster                                                \
  --sshlogin "$SSHHOSTS"                                         \
  --sshdelay=0.5                                                 \
  --basefile "$WORK_DIR"                                         \
  --workdir "$JOBS_DIR/{}"                                       \
  --transferfile "$JOBS_DIR/{}"                                  \
  --return "$JOBS_DIR/{}/antOutput.log"                          \
  --return "$JOBS_DIR/{}/summary.csv"                            \
  --return "$JOBS_DIR/{}/killMap.csv"                            \
  --cleanup                                                      \
  timeout 30m                                                    \
    rsync -a --exclude \".git\" "$WORK_DIR/" "./work" "&&"       \
  export "PATH=/usr/lib/jvm/java-1.8.0/bin:\$PATH" "&&"          \
  cd work "&&"                                                   \
  timeout 480m nice -n 9 "$ANT_CMD"                              \
   -f "$CM_BUILD_XML"                                            \
   "-Dbasedir=$JOBS_DIR/{}/work"                                 \
   "-Dd4j.home=$D4J_HOME"                                        \
   -Dmajor.analysisType=mutation                                 \
   -Dmajor.exportKillMap=true                                    \
   -Dmajor.haltOnFailure=false                                   \
   "-Dmajor.includeMutantsFile=$JOBS_DIR/{}/batchMutantIDs.txt"  \
   mutation.test ">>" "../antOutput.log" "2>&1" "&&"             \
  mv summary.csv killMap.csv ".." ";"                            \
  "main_exitcode=\$?;"                                           \
  cd ".." "&&"                                                   \
  rm -rf work ";"                                                \
  exit "\$main_exitcode"                                         \
  ::: ${batch_ids[@]} || die "parallel failed"

# Collect the jobs' killMaps and summaries into a single file each
head -n1 "$JOBS_DIR/aaaaa/summary.csv" > "$CM_RESULTS_ROOT/$PID/$VID/summary.csv"
head -n1 "$JOBS_DIR/aaaaa/killMap.csv" > "$CM_RESULTS_ROOT/$PID/$VID/killMap.csv"
for f in mutantBatches/batch-*; do
  batch_id=$(extract_batch_id "$f")

  # Copy summary and killMap data
  tail -n+2 "$JOBS_DIR/$batch_id/summary.csv" >> "$CM_RESULTS_ROOT/$PID/$VID/summary.csv"
  tail -n+2 "$JOBS_DIR/$batch_id/killMap.csv" >> "$CM_RESULTS_ROOT/$PID/$VID/killMap.csv"

  # Concatenate all job logs into one
  {
    log_custmut "";
    log_custmut "----------";
    log_custmut "Results for mutant IDs: $(tr '\n' ' ' < "$JOBS_DIR/$batch_id/batchMutantIDs.txt")";
    log_custmut "----------";
    cat "$JOBS_DIR/$batch_id/antOutput.log";
  } >> "$LOG_FILE"
done

# Collect covMap.csv from the work directory
cp "$WORK_DIR/mutants.log" "$WORK_DIR/mutants.context" "$WORK_DIR/covMap.csv"  \
   "$WORK_DIR/testMap.csv" \
   "$CM_RESULTS_ROOT/$PID/$VID/"

log_custmut "Results:"
for f in "$CM_RESULTS_ROOT"/"$PID"/"$VID"/*; do
  log_custmut " * $f"
done
log_custmut "Done!"

cd "$CWD"

# Clean up
rm -rf "$WORK_DIR"
rm -rf "$JOBS_DIR"
