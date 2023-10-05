#
# Performs a Monte Carlo simulation of coverage-based testing to estimate the
# relationship between sampled test ratio and achieved coverage.
#
# This script expects 4 command line arguments: (1) the project ID, (2) the bug
# ID, (3) a path to the results directory, and (4) the output directory.
# Generally, the results directory should be the same as the output directory.
#
# A fifth command line argument, a class name, can be provided. If provided,
# coverage for the given class only will be calculated.
#
args <- commandArgs(trailingOnly=TRUE)
if(length(args) < 4) {
    stop("Usage: Rscript cov_simulation.R <ProjectID> <BugID> <CM_RESULTS_ROOT dir> <out dir> [<class name>]")
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

IN_DIR       <- paste0(RES_ROOT, "/", PID, "/", BID, "f")

CM_CSV       <- paste(IN_DIR, "customized-mutants.csv", sep="/")
COV_MAP_CSV  <- paste(IN_DIR, "covMap.csv", sep="/")

# Include all constants and helper functions
source("sim_core.R")

################################################################################
# Fix the random seed for reproducibility. (The actual seed shouldn't matter for
# a sufficiently large number of runs.)
set.seed(1)

################################################################################
if (is.na(CLASS)) {
  all_classes <- list.files(paste0(IN_DIR, "/score_matrix_slices"))
} else {
  all_classes <- c(CLASS)
}
cat("Found ", length(all_classes), " classes for ", PID, "-", BID, "\n", sep="")

################################################################################
mutants <- getMutants(CM_CSV, PID, BID)
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

# Parallelize simulation for all classes
ret <- foreach (i=1:length(all_classes)) %dopar% {
  class <- all_classes[i]
  mutant_ids  <- unique(mutants[mutants$className == class,,drop=F]$mutantId)
  if (length(mutant_ids)==0) {
    return()
  }
  test_ids <- which(as.logical(colSums(cov_matrix[mutant_ids,,drop=F])))
  simCovTesting(line_matrix, test_ids, class)
}
df <- rbindlist(ret)
if (is.na(CLASS)) {
  write.csv(df, paste0(OUT_DIR, "/", PID, ".coverage.csv"), row.names=F, quote=F)
} else {
  write.csv(df, paste0(OUT_DIR, "/", PID, "-", BID, "-", CLASS, ".coverage.csv"), row.names=F, quote=F)
}
warnings()
