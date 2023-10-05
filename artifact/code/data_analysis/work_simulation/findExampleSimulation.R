#
# This script identifies a set of candidate work simulations that are suitable
# for a motivational example: medium complexity (number of mutants) and medium
# efficiency.
#
# It expects to consume `efficiency/efficiency.csv`.
#
df <- read.csv("efficiency/efficiency.csv")
sort <- df[order(df$Efficiency),]

mask <- sort$Efficiency < 0.9 & sort$Efficiency > 0.6 & sort$MutantsTotal > 50 & sort$EquiRatio < 0.5
cat(paste(sort[mask,]$Class, collapse="\n"))
