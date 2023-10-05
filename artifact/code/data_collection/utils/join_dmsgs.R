# Join a set of dmsgs for a given subject.
#
# usage: Rscript join_dmsgs.R <pid> <bid> <score_matrix_slices_dir> <out_csv>
#
################################################################################
require(data.table)

args <- commandArgs(trailingOnly = TRUE)
pid     <- args[1]
bid     <- args[2]
in_dir  <- args[3]
out_csv <- args[4]

# Check number of arguments
if (length(args)!=4) {
    stop("usage: Rscript join_dmsgs.R <pid> <bid> <score_matrix_slices_dir> <out_csv>")
}

class_list <- list.files(in_dir)

all_dmsgs <- list()

for (i in 1:length(class_list)) {
  class <- class_list[i]
  df <- read.csv(paste(in_dir, class, "run0", "mutants_test0.csv", sep="/"))
  df$projectId <- pid
  df$bugId <- bid
  df$class <- class

  all_dmsgs[[i]] <- df
}

all <- rbindlist(all_dmsgs)
write.csv(all[order(all$mutantId),], out_csv, row.names=F, quote=F)
