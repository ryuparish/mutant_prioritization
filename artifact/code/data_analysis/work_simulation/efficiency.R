#
# Compute overall efficiency from a set of work simulations.
#
# This script expects two arguments: a path to the work simulation and a path to an
# output CSV.
#
require(ggplot2)
require(reshape2)
require(data.table)
require(plyr)
library(foreach)
library(doMC)

args <- commandArgs(trailingOnly=TRUE)
if(length(args) != 2) {
    stop("Usage: Rscript efficiency.R <work simulation dir> <out csv>")
}

N_CPUS <- detectCores()
registerDoMC(N_CPUS)

IN_DIR  <- args[1]
OUT_CSV <- args[2]

SIMS <- list.files(IN_DIR, pattern="()*\\.csv$")

#
# Efficiency computation
#
getEfficiency <- function(x) {
  # Avoid spurious results due to rounding errors; efficiency=0 if Prob=Rnd
  ifelse(abs(sum(x$DiffProbRnd))<=0.01, 0,
    ifelse(sum(x$DiffOptRnd)==0, NA, sum(x$DiffProbRnd)/sum(x$DiffOptRnd)))
}

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

  # These are indeed unique for non-sampled simulations
  lines_total      <- unique(df$LinesTotal)
  lines_covered    <- unique(df$LinesCoveredBase)
  tests_total      <- unique(df$TestsTotal)
  tests_base       <- unique(df$TestsSelectedBase)
  mutants_total    <- unique(df$MutantsTotal)
  mutants_killable <- unique(df$MutantsKillable)

  df <- df[, c("Run", "Strategy", "Step", "NodesRatio")]

  # Casting introduces NAs for missing steps at the end -> NodesRatio has to be 1 for those.
  wide <- dcast(df, Step ~ Strategy, mean, value.var="NodesRatio")
  wide[is.na(wide)] <- 1

  wide$DiffProbRnd <- wide$predictedProbKillsDom - wide$Random
  wide$DiffOptRnd  <- wide$OptimalDom - wide$Random

  overall_efficiency <- getEfficiency(wide)
  if (is.na(overall_efficiency)) {
    cat("Invalid efficiency (", overall_efficiency, "): ", csv, "\n")
  } else if (overall_efficiency > 1.0) {
    cat("Implausible efficiency (", overall_efficiency, "): ", csv, "\n")
  } else if (overall_efficiency < -2.0) {
    cat("Outlier negative efficiency (", overall_efficiency, "): ", csv, "\n")
  }

  return(list(Project=pid, Class=csv,
              Efficiency=overall_efficiency,
              Coverage=lines_covered/lines_total,
              LinesTotal=lines_total,
              TestsRatio=tests_base/tests_total,
              TestsTotal=tests_total,
              EquiRatio=(mutants_total-mutants_killable)/mutants_total,
              MutantsTotal=mutants_total,
              SumProbRnd=sum(wide$DiffProbRnd),
              SumOptRnd=sum(wide$DiffOptRnd),
              MaxSteps=max(wide$Step)))
}
all <- rbindlist(ret)

all <- all[complete.cases(all),]
write.csv(all, OUT_CSV, row.names=F, quote=F)

agg_by_pid <- rbindlist(by(all, all$Project, function(x) list(Project=unique(x$Project), Efficiency=sum(x$SumProbRnd)/sum(x$SumOptRnd))))
cat(paste0(agg_by_pid$Project, " & ", round(agg_by_pid$Efficiency, 2), " \\\\", collapse="\n"), "\n")
cat("\\midrule\n")
cat(paste0("Total & ", round(sum(all$SumProbRnd)/sum(all$SumOptRnd),2)), " \\\\\n")

cat("Distribution of efficiency per project\n")
summary(agg_by_pid$Efficiency)

cat("Distribution of efficiency per class\n")
summary(all$Efficiency)

warnings()
