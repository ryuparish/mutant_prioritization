#
# Compute overall efficiency, given a set of work simulations.
#
# This script expects 2 command line arguments: (1) a work simulation directory
# (e.g., "results/simulations/no_sampling"), and (2) a path to an output CSV
# file.
#
require(ggplot2)
require(reshape2)
require(data.table)
require(plyr)

args <- commandArgs(trailingOnly=TRUE)
if(length(args) != 2) {
    stop("Usage: Rscript efficiency_sample.R <work simulation dir> <out dir>")
}

library(foreach)
library(doMC)
N_CPUS <- detectCores()
registerDoMC(N_CPUS)

IN_DIR  <- args[1]
OUT_CSV <- args[2]

SIMS <- list.files(IN_DIR, pattern="*\\.csv$")

#
# Efficiency computation
#
getEfficiency <- function(x) {
  # Avoid spurious results due to rounding errors; efficiency=0 if Prob=Rnd
  ifelse(sum(x$DiffOptRnd)<=0.01, NA,
    ifelse(abs(sum(x$DiffProbRnd))<=0.01, 0, sum(x$DiffProbRnd)/sum(x$DiffOptRnd)))
}

ret <- foreach (i=1:length(SIMS)) %dopar% {
  csv <- SIMS[[i]]
  # Skip summary files
  if (grepl("summary.csv", csv)) {
    return()
  }

  pid <- gsub("^([^-]*)-.*", "\\1", csv)

  df <- fread(paste(IN_DIR, csv, sep="/"))

  if (nrow(df)==0) {
    cat("No simulation results:", csv, "\n")
    stop()
  }

  if(max(df$NodesRatio)>1) {
    cat("Broken simulation results:", csv, "\n")
    stop()
  }

  # Columns (simulation output):
  # "Strategy", "Run", "Step",
  # "LinesTotal","LinesCoveredBase",
  # "TestsTotal","TestsSelectedBase",
  # "MutantsTotal","MutantsKillable",
  # "MutantId","TestId","MutantUtility","isEqui","isDom","isTriv",
  # "NodesKilled","NodesRatio","Type"

  df$Coverage   <- df$LinesCoveredBase/df$LinesTotal
  df$TestsRatio <- df$TestsSelectedBase/df$TestsTotal
  df$EquiRatio  <- (df$MutantsTotal-df$MutantsKillable)/df$MutantsTotal

  if(max(df$EquiRatio)>1 | min(df$EquiRatio)<0) {
    cat("Implausible mutant numbers:", csv, "\n")
    stop()
  }

  df <- df[, c("Run", "Strategy", "Step", "NodesRatio", "Coverage", "TestsRatio", "EquiRatio", "LinesTotal", "TestsTotal", "MutantsTotal")]

  # Casting introduces NAs for missing steps at the end -> NodesRatio has to be 1 for those.
  wide <- dcast(df, Step + Run + Coverage + TestsRatio + EquiRatio + LinesTotal + TestsTotal + MutantsTotal ~  Strategy, mean, value.var="NodesRatio")
  wide[is.na(wide)] <- 1

  # Compute differences per step
  wide$DiffProbRnd <- wide$predictedProbKillsDom - wide$Random
  wide$DiffOptRnd  <- wide$OptimalDom - wide$Random

  agg_by_run <- rbindlist(by(wide, wide$Run,
                    function(x) list(Project=pid, Class=csv,
                                     Run=unique(x$Run),
                                     Efficiency=getEfficiency(x),
                                     Coverage=unique(x$Coverage),
                                     LinesTotal=unique(x$LinesTotal),
                                     TestsRatio=unique(x$TestsRatio),
                                     TestsTotal=unique(x$TestsTotal),
                                     EquiRatio=unique(x$EquiRatio),
                                     MutantsTotal=unique(x$MutantsTotal),
                                     MaxSteps=max(x$Step)
                                     )))

  return(agg_by_run)
}
all <- rbindlist(ret)

cat(sum(!complete.cases(all)), "invalid Runs (NA efficiency)\n")
all <- all[complete.cases(all),]

summary(all$Efficiency)

write.csv(all, OUT_CSV, row.names=F, quote=F)

warnings()
