# Slice a score matrix into one slice per mutated class; each slice contains all
# mutants for a mutated class.
#
# Note that the score matrix only contains the mutant id, which is the reason
# why we need to join two data files (score matrix and mutant-class mapping).
#
# For each mutated class in the original score matrix, this scripts generates
# the following sub directory and file:
# <out_dir>/<class_name>/scoreMatrix.csv
#
# usage: Rscript split_score_matrix.R <score_matrix.csv> <mutant_class_map.csv> <out_dir>
#
################################################################################

#
# Create a subdirectory and write the score matrix slice for a given class
#
writeSlice2Csv <- function(df) {
  class_name <- unique(df$Class)
  dir.create(file.path(out_dir, class_name))
  write.csv(df[,-2], paste(out_dir, class_name, "scoreMatrix.csv", sep="/"), row.names=F, quote=F, na="")
  return(nrow(df))
}

# Read input files and output directory
args <- commandArgs(trailingOnly = TRUE)
score_matrix <- args[1]
mutant_map   <- args[2]
out_dir      <- args[3]

# Check number of arguments
if (length(args)!=3) {
    stop("usage: Rscript split_score_matrix.R <score_matrix.csv> <mutant_class_map.csv> <out_dir>")
}

# Format of the score matrix: Mutant,TestName_1,...,TestName_n
df.score_matrix <- read.csv(score_matrix)
# Format of the mutant map: Mutant:Target:Line
df.mutant_map   <- read.csv(mutant_map, sep=":")

# Extract the top-level class name
df.mutant_map$Class <- gsub("([^\\$^@]+)(\\$[^@]+)?(@.+)?", "\\1", df.mutant_map$Target)

df <- merge(df.mutant_map[, c("Mutant", "Class")], df.score_matrix, by=c("Mutant"))

by(df, df$Class, function(x) writeSlice2Csv(x))

