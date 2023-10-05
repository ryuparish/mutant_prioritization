#
# This script:
# 1. Computes for each mutant the probability of selecting a dominator-killing
#    test, when randomly sampling from the set of all tests that kill the given mutant.
# 2. Computes additional context features (e.g., nesting and loc).
# 3. Adds pKillsDom and the context features to an existing data file and
#    outputs the final customized-mutants.csv
#
# TODO: Combine the Java implementation (subsumption.jar) that computes some
#       context features with this script, which computes additiona context features.
#
# Usage: Rscript add_features_labels.R <dmsgs.csv> <killmap.csv> <consolidated csv> <output csv>
#
################################################################################
require(data.table)
require(plyr)
library(stringr)

args <- commandArgs(trailingOnly=TRUE)
if(length(args) != 4) {
    stop("Usage: Rscript  add_features_labels.R <dmsgs.csv> <killmap.csv> <consolidated csv> <output csv>")
}
DMSGS    <- args[1]
KILLMAP  <- args[2]
IN_CSV   <- args[3]
OUT_CSV  <- args[4]

################################################################################
#
# Return the list of dominator mutant ids for a given list of mutants
#
getDomMutants <- function(dmsg) {
  return(unique(dmsg[dmsg$dominatorStrength == 1, mutantKey]))
}

################################################################################
#
# Add a unique mutant key: make mutant IDs unique across classes and subjects
#
addUniqueMutantKey <- function(df) {
  df$mutantKey <- paste(df$projectId, df$bugId, df$mutantId, df$class, sep = "-")
  return(df)
}

################################################################################
#
# Add a unique test key: make test IDs unique across classes and subjects
#
addUniqueTestKey <- function(df) {
  df$testKey <- paste(df$projectId, df$bugId, df$TestNo, df$class, sep = "-")
  return(df)
}

################################################################################
#
# Add additional context features -- TODO: move this functionality elsewhere
#
addContext <- function(df) {
  # Compute basic nesting context: number of ifs etc. on the parent path
  df$nestingTotal <- 1 + str_count(df$astStmtContextBasic, "IF|FOR|WHILE|DO")
  df$nestingLoop  <- 1 + str_count(df$astStmtContextBasic, "FOR|WHILE|DO")
  df$nestingIf    <- 1 + str_count(df$astStmtContextBasic, "IF")
  
  # Compute max nesting and ratio
  agg <- aggregate(nestingTotal ~ projectId + bugId + methodName, df, FUN=max)
  names(agg)[names(agg) == 'nestingTotal'] <- 'maxNestingInSameMethod'
  df <- merge(df, agg, by=c("projectId", "bugId", "methodName"))
  df$nestingRatioTotal <- df$nestingTotal/df$maxNestingInSameMethod
  df$nestingRatioLoop  <- df$nestingLoop/df$maxNestingInSameMethod
  df$nestingRatioIf    <- df$nestingIf/df$maxNestingInSameMethod
  
  # Compute number of mutants in same method
  agg <- aggregate(isCovered ~ projectId + bugId + methodName, df, FUN=length)
  names(agg)[names(agg) == 'isCovered'] <- 'numMutantsInSameMethod'
  df <- merge(df, agg, by=c("projectId", "bugId", "methodName"))
  
  # Compute position in method
  agg <- aggregate(lineNumber ~ projectId + bugId + methodName, df, FUN=max)
  names(agg)[names(agg) == 'lineNumber'] <- 'maxLineNumberInSameMethod'
  df <- merge(df, agg, by=c("projectId", "bugId", "methodName"))
  agg <- aggregate(lineNumber ~ projectId + bugId + methodName, df, FUN=min)
  names(agg)[names(agg) == 'lineNumber'] <- 'minLineNumberInSameMethod'
  df <- merge(df, agg, by=c("projectId", "bugId", "methodName"))
  df$lineRatio <- (df$lineNumber-df$minLineNumberInSameMethod)/(df$maxLineNumberInSameMethod-df$minLineNumberInSameMethod)

  return(df)
}
################################################################################

# Read all class-level dmsgs and add a unique mutant key
dmsgs <- fread(DMSGS)
dmsgs <- addUniqueMutantKey(dmsgs)

# List of dominator mutant IDs
all_dom_ids <- getDomMutants(dmsgs)

# Add project ID, bug ID, group ID, and class name to Major's kill map, which
# only provides mutant ID, test ID, and execution result by default.
mut_class_map <- dmsgs[,c("projectId","bugId","mutantId", "groupId", "class")]

# Read the kill map and add mutant and test ids.
kill_map <- fread(KILLMAP)
kill_map$mutantId <- kill_map$MutantNo
kill_map <- join(kill_map, mut_class_map, by=c("mutantId"))
kill_map <- addUniqueMutantKey(kill_map)
kill_map <- addUniqueTestKey(kill_map)

# All dominator mutants and dominator-killing tests
all_doms <- kill_map[kill_map$mutantKey %in% all_dom_ids,]
dom_killing_tests <- unique(all_doms$testKey)

# Introduce a new pKillsDom column and set it to 1 if the test kills a dominator, 0 otherwise.
kill_map$pKillsDom <- 0
kill_map[kill_map$testKey %in% dom_killing_tests, ]$pKillsDom <- 1

prob_map <- kill_map[, c("projectId", "bugId", "class", "mutantId", "pKillsDom")]
prob_map <- aggregate(pKillsDom ~ projectId + bugId + class + mutantId, prob_map, FUN = mean)

# Introduce a new expKilledDomNodes column and set it to the number of distinct
# dmsg groups; set it to 0 if the test does not kill a dominator.
num_dom_nodes <- aggregate(groupId ~ projectId + bugId + class + testKey, all_doms, FUN = function(x) length(unique(x)))
num_dom_nodes$expKilledDomNodes <- num_dom_nodes$groupId
num_dom_nodes <- num_dom_nodes[, c("projectId", "bugId", "class", "testKey", "expKilledDomNodes")]

exp_map <- kill_map[, c("projectId", "bugId", "class", "mutantId", "testKey")]
exp_map <- join(exp_map, num_dom_nodes, by=c("projectId", "bugId", "class", "testKey"), type="full")
exp_map[is.na(exp_map$expKilledDomNodes),]$expKilledDomNodes <- 0

exp_map <- exp_map[, c("projectId", "bugId", "class", "mutantId", "testKey", "expKilledDomNodes")]
exp_map <- aggregate(expKilledDomNodes ~ projectId + bugId + class + mutantId, exp_map, FUN = mean)

# Read the consolidated data file and add the pKillsDom column
final <- fread(IN_CSV)
# Equivalent mutants do not appear in the kill map -> full join introduces NAs
final <- join(final, prob_map[, c("mutantId", "pKillsDom")], by=c("mutantId"), type="full")
final[is.na(final$pKillsDom),]$pKillsDom <- 0
final <- join(final, exp_map[, c("mutantId", "expKilledDomNodes")], by=c("mutantId"), type="full")
final[is.na(final$expKilledDomNodes),]$expKilledDomNodes <- 0

final <- addContext(final)

# Ignore inner classes and update class names
final$className <- gsub("([^\\$^@]+)(\\$[^@]+)?(@.+)?", "\\1", final$className)

# Write the probabilities for all killable mutants
write.csv(final, OUT_CSV, row.names=F, quote=F)
