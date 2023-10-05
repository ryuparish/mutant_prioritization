#
# This script plots the results of a work simulation.

# This script expects two command line arguments. The first argument is a CSV
# produced by the work_simulation.R script. The second argument is a path for an
# output PDF.
#
require(ggplot2)
require(data.table)
require(plyr)

args <- commandArgs(trailingOnly=TRUE)
if(length(args) < 1) {
    stop("Usage: Rscript plot_simulation.R <work simulation csv> <out pdf> [run]")
}

IN_CSV  <- args[1]
OUT_PDF <- args[2]
RUN     <- args[3]

df <- read.csv(IN_CSV, stringsAsFactors=F)
df[df$Strategy=="predictedProbKillsDom",]$Strategy <- "Utility"
df[df$Strategy=="OptimalDom",]$Strategy            <- "Optimal"
df$Strategy <- factor(df$Strategy, c("Optimal", "Utility", "Random"))

if (!is.na(RUN)) {
  df <- df[df$Run==RUN,]
}

# Scale mutant utility to [0,1]
df$ScaledUtility <- df$MutantUtility-min(df[df$Strategy=="Utility",]$MutantUtility)
df$ScaledUtility <- df$ScaledUtility/max(df[df$Strategy=="Utility",]$ScaledUtility)

agg  <- aggregate(NodesRatio~Step+Strategy, df, mean)
min  <- setNames(agg[agg$Strategy=="Random", c("Step", "NodesRatio")], c("Step", "Rnd"))
util <- setNames(agg[agg$Strategy=="Utility", c("Step", "NodesRatio")], c("Step", "Util"))
max  <- setNames(agg[agg$Strategy=="Optimal", c("Step", "NodesRatio")], c("Step", "Opt"))

all <- join(df, min, by=c("Step"), type="full")
all <- join(all, util, by=c("Step"), type="full")
all <- join(all, max, by=c("Step"), type="full")

pdf(OUT_PDF, width=6, height=4)

# Plot the expected work for dominator nodes
ggplot(data=df, aes(x=Step, y=NodesRatio, color=Strategy)) + geom_point(alpha=0.02) +
scale_color_manual(name = "Mutant prioritization", values=c("gray", "blue", "red")) +
stat_summary(fun.y="mean", geom="line", size=1.5, aes(group=Strategy)) +
xlab("Work") + ylab("Test completeness") + theme_bw() + theme(legend.position="top")

ggplot(data=df, aes(x=Step, y=NodesRatio, color=Strategy)) +
scale_color_manual(name = "Mutant prioritization", values=c("gray", "blue", "red")) +
geom_ribbon(data=all, aes(x=Step, ymin=Rnd, ymax=Util), size=0, fill="blue", color="blue", alpha=0.2) +
geom_ribbon(data=all, aes(x=Step, ymin=Util, ymax=Opt), size=0, fill="gray", color="gray", alpha=0.2) +
stat_summary(fun.y="mean", geom="line", size=1.5) +
stat_summary(data=df[df$Strategy=="Utility",], aes(y=ScaledUtility), linetype="dashed", color="black", fun.y="median", geom="line", size=0.5) +
xlab("Work") + ylab("Test completeness") + theme_bw() + theme(legend.position="top")

dev.off()
warnings()
