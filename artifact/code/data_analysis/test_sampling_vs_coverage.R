#
# This script renders sampling ratio against code coverage.
#
# It expects three command line arguments: (1) a path to an input CSV, (2) the  
# name of the class for which to produce the plot, and (3) a path to an output
# PDF. 
#
args <- commandArgs(trailingOnly = TRUE)
IN_CSV     <- args[1]
CLASS_NAME <- args[2]
OUT_PDF    <- args[3]

library(ggplot2)
library(data.table)

cov_df <- read.csv(IN_CSV)
cov_df

pdf(OUT_PDF, width = 6, height = 4)

ggplot(data=cov_df, aes(x = TestsRatio, y = Coverage)) +
    geom_point(alpha = 0.025) +
    geom_smooth(method="glm", method.args = list(family = "quasibinomial")) +
    xlab("Test sampling ratio") + ylab("Code coverage") + theme_bw() 

warnings()