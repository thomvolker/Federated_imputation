#########################################################################################
## Function for synthesizing the data, that handles partitioned data and the           ##
## complete data                                                                       ##
#########################################################################################

synthesize <- function(data, parts = NULL,    # Use a function to synthesize and analyze
                         partition = FALSE, n.parts = 5,
                         method = NULL, m = 1) {   # the (synthesized) data.
  
  if (partition) {
    # If the data must be partitioned every iterations, the function creates the partitions
    partitions <- rep(1/n.parts, n.parts)
    names(partitions) <- paste0("d", 1:n.parts)
    parts <- resample_partition(data, partitions)
  }
  
  if (!is.null(parts)) {
    # If there are partitions included, synthesize synthesize the data of all partitions,
    # and rowbind the synthesized partitions
    syn_dat <- map_dfr(parts, function(x) syn(as.data.frame(x), print.flag = F, m = m, method = method)$syn) 
  }                                           
  else {
    # If it concerns the complete data as a whole, simply synthesize the complete data, 
    # and extract this data
    if (m == 1) syn_dat <- syn(data, print.flag = F, m = m, method = method)$syn
    else syn_dat <- syn(data, print.flag = F, m = m, method = method)
  }
  return(syn_dat)
}

#########################################################################################
## Function for synthesizing the data, that handles partitioned data and the           ##
## complete data                                                                       ##
#########################################################################################

normal_syn <- function(data, method = NULL, formula, pop.inf = F) {
  d   <- data                                             # specify the data
  s1  <- syn(d, m = 1, method = method, print.flag = F)   # 1 synthesis
  s5  <- syn(d, m = 5, method = method, print.flag = F)   # 5 syntheses
  s10 <- syn(d, m = 10, method = method, print.flag = F)  # 10 syntheses
  
  f <- as.formula(formula)                                # the formula
  
  # Fit the lm models on all four datasets (the real data and the synthetic data)
  r <- list(Real_Sample = lm(f,d), Syn1 = lm.synds(f, s1), Syn5 = lm.synds(f, s5), Syn10 = lm.synds(f, s10))
  
  # Collect the output
  out <- map(r, function(x) {if (class(x) == "fit.synds") {x <- summary(x, population.inference = pop.inf)}
    else {x <- summary(x)}
    return(as.data.frame(coef(x)))}) %>% 
    map(., function(x) {colnames(x) <- c("Est", "SE", "stat", "P"); return(as.data.frame(x))}) %>%
    map(., function(x) rownames_to_column(x, var = "Variable")) %>%
    bind_rows(., .id = "Method") %>%
    group_by(Method) %>% 
    ungroup() %>%
    dplyr::select(., Method, Variable, Est, SE, stat, P) %>%
    mutate(Lower = Est - qnorm(.975)*SE,
           Upper = Est + qnorm(.975)*SE)
  # Return the output
  return(as.data.frame(out))
}

#########################################################################################
## Function for generating multivariate normal data with a prespecified correlation    ##
## between the predictors, and a prespecified relative contribution of each IV, as     ##
## well as a prespecified R squared and sample size.                                   ##
#########################################################################################

normal <- function(r2, ratio_beta, rho, n = 10000) {
  # First, draw the covariates from a multivariate normal distribution with means of 0, so
  # that if the variances equal one, and the covariances equal zero, one has a multivariate
  # standard normal distribution. However, of course it is possible to introduce 
  # correlations between the predictors.
  X <- MASS::mvrnorm(n = n, mu = rep(0, length(ratio_beta)), Sigma = rho)
  # Set the variable names (X1, ..., XK results in problems in synthpop)
  colnames(X) <- paste0("IV", 1:length(ratio_beta))
  # Empty matrix for the regression coefficients.
  coefs <- matrix(NA, nrow = length(ratio_beta), ncol = length(ratio_beta))
  for (i in 1:length(ratio_beta)) {
    for (j in 1:length(ratio_beta)) {
      # Set the relative contribution of each pair of regression coefficients to the 
      # population R2 level (relative contribution equals the product of the ratios).
      # Note that only the lower triangle is specified (including the diagonal elements).
      coefs[i,j] <- ifelse(i > j, ratio_beta[i] * ratio_beta[j], 0)
    }
  }
  # b here equals the regression coefficient of the variable which "ratio" would be 
  # as being equal to 1. If the ratio equals two, the regression coefficient should be
  # equal to two times b. 
  b <- sqrt((r2 / (sum(ratio_beta^2) + 2 * sum(coefs * rho))))
  # Specify the outcome variable of interest.
  y <- X %*% (b*ratio_beta) + rnorm(n, 0, sqrt(1 - r2))
  # Return the complete data, and the population regression coefficients.
  return(list(dat = data.frame(DV = y, X), coefs = b*ratio_beta))
}


#########################################################################################
## Function for synthesizing partitioned data, with M synthetic versions of J          ##
## partitions, with a user-defined method of synthesization and user-defined method    ##
## of inference (sample based or population based)                                     ##
#########################################################################################

syn_part_data <- function(partitioned_data, M, formula, visit,
                          method = NULL, pop.inf = T) {
  
  d <- partitioned_data # short code for the partitioned data
  f <- formula          # short code for the formula
  
  # Synthesize every partition of the data M times with method = method
  out <- map(d, function(x) syn(as.data.frame(x), m = M, print.flag = F,
                                method = method, visit.sequence = visit))
  # Set an empty list for every synthetic dataset
  new_syns <- as.list(1:M)
  
  # For every all partitions, extract the first, second, ..., m synthetic versions,
  # and rbind the first synthetic version of all datasets, the second, and so on, so that
  # one obtains M synthetic complete datasets
  for (m in 1:M) {
    new_syns[[m]] <- map_dfr(1:length(out), function(x) out[[x]]$syn[[m]])
  }
  # Extract one class == synds object, so that the lm function in the synthpop package
  # remains usable (the analyses do not rely on anything else than the synthetic data,
  # except for the number of synthetic datasets (which remains preserved)). However,
  # it might be better to write a custom function in the future, this is a quick and 
  # dirty fix
  syn <- out[[1]]
  # Add all synthesized versions to the syn-list of a single "syn" output object
  syn$syn <- new_syns 
  
  data <- map_dfr(d, function(x) as.data.frame(x)) # extract the actually observed data
  
  # Fit the lm models on all datasets
  r <- list(Real_Sample = lm(f,data), Syn = lm.synds(f, syn))
  
  # Collect the output
  out <- map(r, function(x) {if (class(x) == "fit.synds") {x <- summary(x, population.inference = pop.inf)}
    else {x <- summary(x)}
    return(as.data.frame(coef(x)))}) %>% 
    map(., function(x) {colnames(x) <- c("Est", "SE", "stat", "P"); return(as.data.frame(x))}) %>%
    map(., function(x) rownames_to_column(x, var = "Variable")) %>%
    bind_rows(., .id = "Method") %>%
    group_by(Method) %>% 
    ungroup() %>%
    dplyr::select(., Method, Variable, Est, SE, stat, P) %>%
    mutate(Lower = Est - qnorm(.975)*SE,
           Upper = Est + qnorm(.975)*SE)
  # Return the output
  return(as.data.frame(out))
}

#########################################################################################
## Simple extracting of the output of the syn_part_data                                ##
#########################################################################################

print_results <- function(output, coefs) {
  output %>%
    mutate(RealEst = rep(coefs, nrow(output)/length(coefs)),
           Covered = Lower < coefs & Upper > coefs,
           Bias = Est - RealEst) %>%
    ungroup() %>% group_by(Method, Variable) %>%
    summarise("Population estimate" = unique(RealEst),
              "Qbar" = mean(Est),
              "Bias" = mean(Bias),
              "MeanSE" = mean(SE),
              "MinSE" = min(SE),
              "MaxSE" = max(SE),
              "Lower" = mean(Lower),
              "Upper" = mean(Upper),
              "CIW" = mean(Upper) - mean(Lower),
              "Coverage" = mean(Covered)) %>%
    arrange(factor(Method, levels = c("Real_Sample", "Syn1", "Syn5", "Syn10")))
}

