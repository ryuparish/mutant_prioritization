#
# This script plots the aggregated efficiency results; it consumes the output of
# the efficiency.R script.
#
# It takes two arguments: `plot_efficiency.R IN_CSV OUT_PDF`. It reads the given
# `IN_CSV` and plots to `OUT_PDF`.
#
require(ggplot2)
require(data.table)
require(plyr)
require(RColorBrewer)

args <- commandArgs(trailingOnly=TRUE)
if(length(args) != 2) {
    stop("Usage: Rscript plot_efficiency.R <efficiency csv> <out pdf>")
}

IN_CSV  <- args[1]
OUT_PDF <- args[2]

df <- read.csv(IN_CSV)
df$CovGrp <- ""

agg_by_pid <- rbindlist(by(df, df$Project, function(x) list(Project=unique(x$Project), Efficiency=sum(x$SumProbRnd)/sum(x$SumOptRnd))))

for (p in unique(df$Project)) {
  m <- df$Project==p
  df[m, ]$CovGrp <- cut(df[m,]$Coverage, 4)
}
c <- brewer.pal(4,"Blues")

# Coverage will be zero in the no_sampling efficiency CSVs, so
# covGrp will have one value (quartile).
if (length(unique(df$CovGrp))==1) {
  p <- ggplot(data=df, aes(x=Project, y=Efficiency)) + ylim(-2,1) +
  geom_hline(yintercept=0, color = "red", size=1) +
  geom_hline(yintercept=1, color = "gray", size=1) +
  geom_boxplot(fill="blue", alpha=0.4) +
  xlab("Project") + ylab("Efficiency") + theme_bw() + theme(legend.position="top")
} else {
  p <- ggplot(data=df, aes(x=Project, y=Efficiency)) + ylim(-2,1) +
  scale_fill_manual(name = "Coverage quartile", values=c) +
  geom_hline(yintercept=0, color = "red", size=1) +
  geom_hline(yintercept=1, color = "gray", size=1) +
  geom_boxplot(aes(fill=CovGrp), alpha=0.4) +
  xlab("Project") + ylab("Efficiency") + theme_bw() + theme(legend.position="top")
}

pdf(OUT_PDF, width=8, height=4)
p
dev.off()

warnings()
