#
# This file provides a number of constants and custom functions for the monte
# carlo simulations (e.g., work_simulation.R).
#
# It is not intended to be used directly by a user.
#
require(data.table)
require(plyr)

# Number of runs for each strategy
N_RUNS <- 1000

# Run all these strategies
STRATEGIES <- c("predictedProbKillsDom", "OptimalDom", "Random")

#
# Take Major's kill map and test map, perform sanity checking and return the
# kill map -- maintain the long format, which makes the simulation much easier.
#
# Add mutantId column (=MutantNo) for consistency
#
getKillMatrix <- function(kill_map_csv, test_map_csv) {
    kill_map    <- fread(kill_map_csv)
    kill_map$mutantId <- kill_map$MutantNo
    return(kill_map)
}

#
# Augment Major's coverage map with line-number information for each mutant
#
getCovMap <- function(cov_map_csv, cust_mut) {
    cov_map <- fread(cov_map_csv)

    cov_map$mutantId <- cov_map$MutantNo
    cov_map <- join(cov_map, cust_mut[, c("mutantId", "lineNumber")], by=c("mutantId"))

    return(cov_map)
}


#
# Reads the prediction results and returns the data in wide format:
# * Each row corresponds to one mutant and provides all predictions
#
getPredictions <- function(input_csv, pid, bid, mutants_df) {
    predictions <- fread(input_csv)
    # Filter current subject
    predictions <- predictions[predictions$projectId==pid & predictions$bugId==bid,]

    # Random: all mutants have the same utility (the simulation reshuffles on
    # every run, so no need to do anything fancy here)
    predictions$Random <- 0.5

    # Optimal: rank mutants by expected number of dom nodes killed; use isDom as
    # a tie breaker to distinguish between dom and sub nodes.
    predictions$OptimalDom <- as.numeric(0)
    predictions[order(predictions$mutantId),]$OptimalDom <- mutants_df[order(mutants_df$mutantId),]$expKilledDomNodes + (mutants_df[order(mutants_df$mutantId),]$isDom/100) 
    return(predictions)
}

#
# Reads the meta data and ground-truth data for all mutants
#
getMutants <- function(cust_mut_csv, pid, bid) {
    mutants <- fread(cust_mut_csv)
    # Filter current subject and covered mutants
    mutants <- mutants[mutants$projectId==pid & mutants$bugId==bid & isCovered==1,]

    return(mutants)
}

#
# Read the dmsg details and retain non-equivalent mutants
#
getDMSG <- function(dmsgs_csv, pid, bid) {
    dmsg <- fread(dmsgs_csv)
    # Filter current subject
    dmsg <- dmsg[dmsg$projectId==pid & dmsg$bugId==bid,]
    # Retain only non-equivalent mutants
    dmsg <- dmsg[dmsg$dominatorStrength>=0,]

    return(dmsg)
}

#
# Returns a list of all trivial mutants
#
getAllTrivialMutants <- function(mutants) {
    return(mutants[mutants$isTrivial==1, mutantId])
}

#
# Returns the list of all live mutants in the provided kill map
#
getKillableMutants <- function(kill_map) {
    return(unique(kill_map$MutantNo))
}

#
# Return the list of dominator node ids for a given list of mutants
#
getDomNodes <- function(dmsg, mutants) {
    return(unique(dmsg[dmsg$dominatorStrength==1 & dmsg$mutantId %in% mutants, groupId]))
}

#
# Return the list of dominator mutant ids for a given list of mutants
#
getDomMutants <- function(dmsg, mutants) {
    return(unique(dmsg[dmsg$dominatorStrength==1 & dmsg$mutantId %in% mutants, mutantId]))
}

#
# Performs the complete work simulation (all runs for all strategies) for a given class
#
runSimulation <- function(kill_matrix, cov_matrix, line_matrix, cov_sim, class, mutants, all_predictions, out_csv, sample=F) {
  # Filter mutant ids by class
  mutant_ids         <- unique(mutants[mutants$className == class,]$mutantId)
  num_mutants_class  <- length(mutant_ids)
  num_mutants        <- num_mutants_class

  mutant_mask <- logical(nrow(kill_matrix))
  mutant_mask[mutant_ids] <- T

  # All test ids for tests that cover at least one mutant in this class
  test_ids  <- which(as.logical(colSums(cov_matrix[mutant_ids,,drop=F])))
  num_tests <- length(test_ids)

  # No mutants in this class -> skip
  if (num_mutants==0) {
    return(list(Class=class, MutantsTotal=0, MutantsKillable=0, TestsTotal=num_tests, SimRuns=-1))
  }

  all_killable_mutants       <- which(kill_matrix[mutant_ids, KM_KILLABLE]==T)
  num_killable_mutants_class <- length(all_killable_mutants)
  num_killable_mutants       <- num_killable_mutants_class

  # All mutants are equivalent -> skip
  if (num_killable_mutants==0) {
    return(list(Class=class, MutantsTotal=num_mutants, MutantsKillable=num_killable_mutants, TestsTotal=num_tests, SimRuns=-1))
  }

  # Only one mutant: exp efficiency is identical for all strategies -> skip
  if (num_mutants==1) {
    return(list(Class=class, MutantsTotal=num_mutants, MutantsKillable=num_killable_mutants, TestsTotal=num_tests, SimRuns=-1))
  }

  all_dom_nodes     <- unique(kill_matrix[mutant_mask & kill_matrix[, KM_DOM] == T, KM_GRP])
  num_all_dom_nodes <- length(all_dom_nodes)

  predictions <- all_predictions[all_predictions$mutantId %in% mutant_ids,]

  # Column indices for the simulation map
  UTIL   <- 1
  KILLED <- 2
  STEP   <- 3
  TEST   <- 4

  sim_map <- matrix(nrow=nrow(kill_matrix), ncol=TEST, 0)

  # List of all individual work simulations (across all strategies and runs).
  all_sims <- vector("list", length(STRATEGIES)*N_RUNS*num_killable_mutants)
  sim_index <- 1
  if (PROFILING) { Rprof("sim_prof.out") }

  # Sample one initial test suite for each run and determine the set of killed
  # mutants for each test suite
  if (sample) {
    m <- lm(log(TestsRatio)~Coverage, cov_sim[Class==class,])
    U <- list(runif(N_RUNS))
    names(U) <- c("Coverage")
    R <- exp(predict(m, U))
    N <- ceiling(R * length(test_ids))

    killed_masks  <- vector("list", N_RUNS)
    base_coverage <- vector("list", N_RUNS)
    base_killable <- vector("list", N_RUNS)
    for (i in 1:N_RUNS) {
      selected_test_ids  <- sampleTests(line_matrix, test_ids, N[i])
      killed_masks[[i]]  <- as.logical(rowSums(kill_matrix[, selected_test_ids, drop=F]))==T
      base_coverage[[i]] <- sum(sign(rowSums(line_matrix[, selected_test_ids, drop=F])))
      mask <- mutant_mask & !killed_masks[[i]]

      base_killable[[i]] <- sum(kill_matrix[mask, KM_KILLABLE])
    }
  }

  total_lines <- sum(sign(rowSums(line_matrix[, test_ids, drop=F])))

  for(strategy in STRATEGIES) {
      predictions$Utility <- predictions[[strategy]]
      sim_map[predictions$mutantId, UTIL] <- predictions$Utility

      for(run in seq(1:N_RUNS)) {
          # Init the simulation map with a step number greater than the max mutant ID
          # a mutant is always killed at the earliest step --- by the first test
          # that can kill it
          sim_map[, STEP]   <- nrow(sim_map)+1
          sim_map[, TEST]   <- -1
          sim_map[, KILLED] <- F

          base_all_dom_nodes     <- num_all_dom_nodes
          num_killed_dom_nodes   <- 0
          ratio_killed_dom_nodes <- 0
          base_tests        <- 0
          base_lines             <- 0
          step                   <- 0
          test_id                <- -1

          # Remove all mutants killed by pre-sampled tests and update test completeness
          if (sample) {
            # Skip the simulation if all mutants are already killed
            num_killable_mutants <- base_killable[[run]]
            if (num_killable_mutants == 0) {
              next
            }
            num_mutants <- sum(mutant_mask & !killed_masks[[run]])

            sim_map[killed_masks[[run]], STEP]   <- -1
            sim_map[killed_masks[[run]], TEST]   <- -1
            sim_map[killed_masks[[run]], KILLED] <- T

            mask <- mutant_mask & killed_masks[[run]] & kill_matrix[, KM_DOM] == T

            base_all_dom_nodes <- num_all_dom_nodes - length(unique(kill_matrix[mask, KM_GRP]))
            base_tests         <- N[[run]]
            base_lines         <- base_coverage[[run]]
          }
  
          if(BREAK_TIES) {
              # Shuffle predictions data frames to arbitrarily break ties for tied mutants
              predictions <- predictions[sample(nrow(predictions)),]
              predictions$rnd <- 1:nrow(predictions)
          }
  
          # Rank mutants by utility
          ranked_mutants <- predictions[order(-predictions$Utility,predictions$rnd), mutantId]
  
          # The actual simulation: select mutants from the ranked list
          for(id in ranked_mutants) {

              # Non-equivalent killed mutant (already killed in a previous step)
              if (sim_map[id, KILLED]) {
                  next
              }

              # Equivalent and live, non-equivalent mutants count as an actual work step
              step <- step + 1
  
              # Live, non-equivalent mutant
              if (kill_matrix[id, KM_KILLABLE]) {
                  # Randomly sample a test that kills the mutant
                  tests <- which(kill_matrix[id,-KM_EXCL]==T)
                  # If there is only one test, return that test (don't use sample here as it
                  # will return a value between 1 and that test's id)
                  if (length(tests)==1) {
                      test_id <- tests[1]
                  } else {
                      test_id <- sample(tests, 1)
                  }
  
                  # Set mutant properties
                  is_equi <- 0
                  is_dom  <- kill_matrix[id, KM_DOM]
                  is_triv <- kill_matrix[id, KM_TRIV]
  
                  sim_map[id, c(STEP, TEST)] <- c(step, test_id)
  
                  # Determine all mutants killed by this test
                  killed <- mutant_mask & kill_matrix[, test_id]==T
                  sim_map[killed, KILLED] <- T
                  sim_map[killed, STEP] <- pmin(sim_map[killed, STEP], step)
                  killed_doms <- sim_map[, STEP]==step & kill_matrix[, KM_DOM]==T
                  num_killed_dom_nodes <- num_killed_dom_nodes + length(unique((kill_matrix[killed_doms, KM_GRP])))
                  ratio_killed_dom_nodes <- num_killed_dom_nodes / base_all_dom_nodes
              }
              # Equivalent mutant
              else {
                  # Since this step selected an equivalent mutant, it did not select a
                  # test and all numbers and ratios remain the same.
                  is_equi <- 1
                  is_dom  <- 0
                  is_triv <- 0
  
                  # Just set the step -> no test
                  test_id <- -1
                  sim_map[id, STEP] <- step
              }
  
              # The prediction mutant utility
              mutant_util <- sim_map[id, UTIL]
  
              all_sims[[sim_index]] <- list(Strategy=strategy, Run=run, Step=step,
                                       LinesTotal=total_lines, LinesCoveredBase=base_lines,
                                       TestsTotal=num_tests, TestsSelectedBase=base_tests,
                                       MutantsTotal=num_mutants, MutantsKillable=num_killable_mutants,
                                       MutantId=id, TestId=test_id, MutantUtility=mutant_util,
                                       isEqui=is_equi, isDom=is_dom, isTriv=is_triv,
                                       NodesKilled=num_killed_dom_nodes, NodesRatio=ratio_killed_dom_nodes)
  
              sim_index <- sim_index + 1
          }
      }
  }
  # Merge all list entries (data frames for individual simulation runs) into a single data frame
  result <- rbindlist(all_sims)
  if (PROFILING) { Rprof(NULL) }

  # Sanity check: filter results with 0 actual work simulations
  # (e.g., if all sampled test suites kill all mutants).
  if (nrow(result)==0) {
    return(list(Class=class, MutantsTotal=num_mutants_class, MutantsKillable=num_killable_mutants_class, TestsTotal=num_tests, SimRuns=0))
  }
  # Simplify plotting by encoding the type of a mutant
  result$Type   <- ifelse(result$isEqui==1, "Equi", ifelse(result$isDom==1, "Dom", "Sub"))

  # Write the final data frame to a csv file
  write.csv(result, out_csv, row.names=F)

  num_runs <- nrow(unique(cbind(result$Strategy,result$Run)))
  return(list(Class=class, MutantsTotal=num_mutants_class, MutantsKillable=num_killable_mutants_class, TestsTotal=num_tests, SimRuns=num_runs))
}

#
# Sample up to n tests at random, including the first test that satisfies an
# additional test goal. If the sampled test suite of size m < n satisfies all
# test goals, no further tests are sampled.
#
sampleTests <- function(line_matrix, test_ids, n) {

    coverable <- sum(sign(rowSums(line_matrix[,test_ids,drop=F])))
    num_tests <- length(test_ids)

    shuf <- sample(test_ids)
    sig_cov <- line_matrix[, shuf[1]]
    covered <- sum(sig_cov)

    sampled_ids <- numeric(n)
    sampled_ids[1] <- test_ids[1]

    i <- 1
    num_sampled <- 1
    while (covered < coverable & num_sampled < n) {
        i <- i + 1
        sig <- line_matrix[, shuf[i]]
        sig_cov <- sign(sig_cov + sig)
        if (sum(sig_cov) == covered) {
            next
        }
        covered <- sum(sig_cov)
        num_sampled <- num_sampled + 1
        sampled_ids[num_sampled] <- shuf[i]
    }
    return(sampled_ids[1:num_sampled])
}

#
# Coverage-based testing simulation: select tests at random until the sampled
# test suite satisfies all coverage goals.
#
simCovTesting <- function(line_matrix, test_ids, class) {

    coverable <- sum(sign(rowSums(line_matrix[,test_ids,drop=F])))
    num_tests <- length(test_ids)

    samples <- vector("list", N_RUNS*num_tests)
    index <- 1
    for(run in seq(1:N_RUNS)) {
        shuf <- sample(test_ids)
        sig_cov <- line_matrix[, shuf[1]]
        covered <- sum(sig_cov)
        n <- 1
        samples[[index]] <- list(Class=class, Run=run, Tests=n, TestsRatio=n/num_tests, Coverage=covered/coverable)
        index <- index + 1

        i <- 2
        while (covered < coverable) {
            sig <- line_matrix[, shuf[i]]
            i <- i + 1
            sig_cov <- sign(sig_cov + sig)
            if (sum(sig_cov) == covered) {
              next
            }
            covered <- sum(sig_cov)
            n <- n + 1
            samples[[index]] <- list(Class=class, Run=run, Tests=n, TestsRatio=n/num_tests, Coverage=covered/coverable)
            index <- index + 1
        }
    }
    return(rbindlist(samples))
}
