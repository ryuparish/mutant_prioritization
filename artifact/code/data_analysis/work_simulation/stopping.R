#
# Compute and output average test completeness over mutant utility, given a set
# of work simulations.
#
# This script expects 2 command line arguments: (1) a work simulation directory (e.g.,
# "results/simulations/no_sampling"), and (2) a path for an output CSV.
#
# This output CSV is usually consumed by plot_stopping.R.
#
require(ggplot2)
require(reshape2)
require(data.table)
require(plyr)

args <- commandArgs(trailingOnly=TRUE)
if(length(args) != 2) {
    stop("Usage: Rscript stopping.R <work simulation dir> <out csv>")
}

library(foreach)
library(doMC)
N_CPUS <- detectCores()
registerDoMC(N_CPUS)

IN_DIR  <- args[1]
OUT_CSV <- args[2]

SIMS <- list.files(IN_DIR, pattern="()*\\.csv$")

ret <- foreach (i=1:length(SIMS)) %dopar% {
  csv <- SIMS[[i]]
  # Skip summary files
  if (grepl("summary.csv", csv)) {
    return()
  }
  df <- fread(paste(IN_DIR, csv, sep="/"))
  pid <- gsub("^([^-]*)-.*", "\\1", csv)

  if(max(df$NodesRatio)>1) {
    cat("Broken simulation results:", csv, "\n")
  }

  # Columns (simulation output):
  # "Strategy", "Run", "Step",
  # "LinesTotal","LinesCoveredBase",
  # "TestsTotal","TestsSelectedBase",
  # "MutantsTotal","MutantsKillable",
  # "MutantId","TestId","MutantUtility","isEqui","isDom","isTriv",
  # "NodesKilled","NodesRatio","Type"

  df <- df[df$Strategy=="predictedProbKillsDom", c("Run", "Step", "MutantUtility", "NodesRatio", "LinesTotal", "MutantsTotal")]

  agg <- aggregate(.~Step+MutantUtility+NodesRatio, df, mean)

  return(list(Project=pid, Class=csv, Utility=agg$MutantUtility, TestCompleteness=agg$NodesRatio, LinesTotal=agg$LinesTotal, MutantsTotal=agg$MutantsTotal, MaxSteps=max(agg$Step)))
}
all <- rbindlist(ret)

write.csv(all, OUT_CSV, row.names=F, quote=F)

warnings()
