#
# This script plots the "mutant utility as a stopping criterion" results.
#
# This script expects two command line arguments. The first argument is the path
# to a CSV produced by the "stopping.R" script. The second argument is a path
# to the output PNG.
#
require(ggplot2)
require(data.table)
require(plyr)
require(sigmoid)

args <- commandArgs(trailingOnly=TRUE)
if(length(args) != 2) {
    stop("Usage: Rscript plot_stopping.R <plotting csv> <out png>")
}

IN_CSV  <- args[1]
OUT_PNG <- args[2]

df <- read.csv(IN_CSV)

df$Size  <- ifelse(df$MutantsTotal<10, "Small", ifelse(df$MutantsTotal<100, "Medium", "Large"))
df$Steps <- ifelse(df$MaxSteps<10, "Small", ifelse(df$MutantsTotal<100, "Medium", "Large"))

df$Utility <- (df$Utility-min(df$Utility))/(max(df$Utility)-min(df$Utility))

summary(df$Utility)

#model <- function(x) {
#  m <- lm(TestCompleteness ~ Utility, x)
#  c <- cor.test(1-x$Utility, x$TestCompleteness, method="spearman")
#  p <- c$p.value
#  e <- c$estimate
#
#  cat(unique(x$Project), e, p, "\n")
#
#  print(summary(m))
#  return(m)
#}
#
#
#ret <- by(df, df$Project, function(x) model(x))

png(OUT_PNG, width=3000, height=1800, res=300)

ggplot(data=df, aes(x=Utility, y=TestCompleteness)) +
geom_point(alpha=0.01) +
geom_smooth(method="glm", method.args = list(family = "quasibinomial")) +
facet_wrap(.~Project, ncol=3) + scale_x_reverse() +
xlab("Utility") + ylab("Test Completeness") + theme_bw() 

dev.off()
warnings()
