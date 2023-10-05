#
# This script performs a Monte Carlo simulation to estimate the work required to
# perform mutation-based testing, using different rankings of mutants.
#
# This script expects 4 command line arguments: (1) the project ID, (2) the bug
# ID, (3) a path to the results directory, and (4) the output directory.
# Generally, the results directory should be the same as the output directory.
#
# A fifth command line argument, a class name, can be provided. If provided,
# simulation only for the given class will be calculated.
#
args <- commandArgs(trailingOnly=TRUE)
if(length(args) < 4) {
    stop("Usage: Rscript work_simulation.R <ProjectID> <BugID> <CM_RESULTS_ROOT dir> <out dir> [<class name>]")
}
PID       <- args[1]
BID       <- args[2]
RES_ROOT  <- args[3]
OUT_DIR   <- args[4]
CLASS     <- args[5]

library(ggplot2)
library(data.table)
library(plyr)
library(foreach)
library(doMC)
N_CPUS <- detectCores()
registerDoMC(N_CPUS)
# For non-Unix platforms
#library(doParallel)
#registerDoParallel(N_CPUS)

IN_DIR       <- paste0(RES_ROOT, "/", PID, "/", BID, "f")

CM_CSV       <- paste(IN_DIR, "customized-mutants.csv", sep="/")
DMSGS_CSV    <- paste(IN_DIR, "dmsgs.csv", sep="/")
KILL_MAP_CSV <- paste(IN_DIR, "killMap.csv", sep="/")
COV_MAP_CSV  <- paste(IN_DIR, "covMap.csv", sep="/")
COV_SIM_CSV  <- paste(RES_ROOT, "cov_simulation", paste0(PID, ".coverage.csv"), sep="/")
TEST_MAP_CSV <- paste(IN_DIR, "testMap.csv", sep="/")
PRED_CSV     <- paste(RES_ROOT, "predictions.csv", sep="/")

# Include all constants and helper functions
source("sim_core.R")

# Drop all trivial mutants from consideration?
RM_TRIVIAL <- FALSE

# Break ties (mutants tied on utility) arbitrarily?
# (The default order for tied mutants is by mutant id)
BREAK_TIES <- TRUE

# Enable profiling
PROFILING <- FALSE

s <- as.logical(Sys.getenv("CM_SAMPLE"))
SAMPLE <- !is.na(s) & s

################################################################################
# Fix the random seed for reproducibility. (The actual seed shouldn't matter for
# a sufficiently large number of runs.)
set.seed(1)

################################################################################
# Read customized-mutants file for ground truth
mutants <- getMutants(CM_CSV, PID, BID)

# Read the DMSG details
dmsg <- getDMSG(DMSGS_CSV, PID, BID)

# Read prediction results for mutant utility
all_predictions <- getPredictions(PRED_CSV, PID, BID, mutants)

# Read the kill map and perform some sanity checks on the data
kill_map <- getKillMatrix(KILL_MAP_CSV, TEST_MAP_CSV)

all_killable_mutants     <- getKillableMutants(kill_map)
all_trivial_mutants      <- getAllTrivialMutants(mutants)
all_doms                 <- mutants[mutants$isDominator==1, mutantId]

if (is.na(CLASS)) {
  all_classes <- list.files(paste0(IN_DIR, "/score_matrix_slices"))
} else {
  all_classes <- c(CLASS)
}
cat("Found ", length(all_classes), " classes for ", PID, "-", BID, "\n", sep="")

################################################################################
# Column indices for simulation maps
KM_MAX_TEST <- max(kill_map$TestNo)
KM_DOM      <- KM_MAX_TEST + 1
KM_TRIV     <- KM_MAX_TEST + 2
KM_GRP      <- KM_MAX_TEST + 3
KM_KILLABLE <- KM_MAX_TEST + 4
KM_EXCL     <- c(KM_DOM:KM_KILLABLE)

cat("Building indicator matrix ... ")

kill_matrix <- matrix(nrow=max(mutants$mutantId), ncol=KM_KILLABLE, F)
tids <- unique(kill_map$TestNo)
for (id in tids) {
  mids <- kill_map[TestNo==id, MutantNo]
  kill_matrix[mids, id] <- T
}
kill_matrix[all_doms, KM_DOM] <- T
kill_matrix[all_trivial_mutants, KM_TRIV] <- T
kill_matrix[dmsg$mutantId, KM_GRP] <- dmsg$groupId
kill_matrix[all_killable_mutants, KM_KILLABLE] <- T

cat("done.\n")
print(object.size(kill_matrix), units="Mb")

cov_map <- getCovMap(COV_MAP_CSV, mutants)
cat("Building mutant-coverage matrix ... ")
cov_matrix <- matrix(nrow=max(cov_map$mutantId), ncol=max(cov_map$TestNo), F)
tids <- unique(cov_map$TestNo)
for (id in tids) {
  mids <- cov_map[TestNo==id, mutantId]
  cov_matrix[mids, id] <- T
}
cat("done.\n")
print(object.size(cov_matrix), units="Mb")

cat("Building line-coverage matrix ... ")
line_matrix <- matrix(nrow=max(cov_map$lineNumber), ncol=max(cov_map$TestNo), F)
tids <- unique(cov_map$TestNo)
for (id in tids) {
  lids <- cov_map[TestNo==id, lineNumber]
  line_matrix[lids, id] <- T
}
cat("done.\n")
print(object.size(line_matrix), units="Mb")

cat("Loading coverage-simulation results ... ")
cov_sim <- fread(COV_SIM_CSV)
cat("done.\n")

# Parallelize simulation for all classes
ret <- foreach (i=1:length(all_classes)) %dopar% {
  class <- all_classes[i]
  runSimulation(kill_matrix, cov_matrix, line_matrix, cov_sim, class, mutants, all_predictions, paste0(OUT_DIR, "/", PID, "-", BID, "-", class, ".csv"), sample=SAMPLE)
}
logs <- rbindlist(ret)
log_csv <- paste0(OUT_DIR, "/", PID, "-", BID, "-summary.csv")
write.csv(logs, log_csv, row.names=F, quote=F)
warnings()

if (PROFILING) { summaryRprof("sim_prof.out") }
