
# All simulations draw from a multivariate normal: mu = expected value per party (or district), Sigma built from the
# per-party SDs and an empirical correlation matrix (Sigma = diag(sd) %*% cor %*% diag(sd)).

# National Simulation -----------------------------------------------------------------------------------------------

summarise_polls <- function(polls_adj){
  weighted_vote_share <- polls_adj %>%
    summarise(across(c(ÖVP:KEINE), ~ weighted.mean(., polls_adj$total_weight, na.rm = TRUE))) %>%
    pivot_longer(cols = c(ÖVP:KEINE), names_to = "party", values_to = "polling_avg")

  weighted_moe <- polls_adj %>%
    summarise(across(c(ÖVP_moe:KEINE_moe), ~ weighted.mean(., polls_adj$total_weight, na.rm = TRUE))) %>%
    pivot_longer(cols = c(ÖVP_moe:KEINE_moe), names_to = "party", values_to = "moe") %>%
    mutate(party = str_replace(party, "_moe", ""))

  weighted_vote_share %>%
    left_join(weighted_moe, by = "party") %>%
    left_join(party_order, by = "party") %>% arrange(order) %>% select(-order)
}

sim_national_vote <- function(polls_adj, nat_correlation_matrix, n_simulations = 10^4){
  polling_avg_df <- summarise_polls(polls_adj)

  polling_avg <- polling_avg_df %>% pull(polling_avg)
  std_dev <- polling_avg_df %>% pull(moe)

  cov_matrix <- diag(std_dev) %*% nat_correlation_matrix %*% diag(std_dev)

  set.seed(123)
  simulated_data <- MASS::mvrnorm(n = n_simulations, mu = polling_avg, Sigma = cov_matrix)

  simulated_data %>%
    as.data.frame() %>%
    setNames(party_order$party) %>%
    mutate(sim_id = row_number()) %>%
    pivot_longer(cols = c(ÖVP:KEINE), names_to = "party", values_to = "result") %>%
    # floors on simulated shares (KPÖ 0.7%, everyone else 0.1%)
    mutate(result = case_when(party == "KPÖ" & result < 0.007 ~ 0.007,
                              result < 0.001 ~ 0.001,
                              T ~ result))
}

# Turnout Simulation ------------------------------------------------------------------------------------------------

# National turnout ~ N(recency-weighted mean, sd/2), plus correlated district deviations from the national figure
sim_turnout <- function(regional_turnout, turnout_correlation_matrix, pred_nat_turnout, pred_nat_turnout_sd,
                        n_simulations = 10^4){
  national_turnout <- rnorm(n = n_simulations, mean = pred_nat_turnout, sd = pred_nat_turnout_sd/2) %>%
    as.data.frame() %>%
    setNames(c("pred_national_turnout")) %>%
    mutate(sim_id = row_number())

  rel_turnout_avg <- regional_turnout %>% arrange(GKZ) %>% pull(rel_participation)
  std_dev <- regional_turnout %>% arrange(GKZ) %>% pull(rel_participation_sd)

  cov_matrix <- diag(std_dev) %*% turnout_correlation_matrix %*% diag(std_dev)

  set.seed(123)
  simulated_data <- MASS::mvrnorm(n = n_simulations, mu = rel_turnout_avg, Sigma = cov_matrix)

  simulated_data %>%
    as.data.frame() %>%
    setNames(regional_turnout %>% arrange(GKZ) %>% pull(GKZ)) %>%
    mutate(sim_id = row_number()) %>%
    pivot_longer(cols = c(G1A000:G9G000), names_to = "GKZ", values_to = "pred_rel_turnout") %>%
    left_join(national_turnout, by = "sim_id") %>%
    mutate(pred_participation = pred_national_turnout + pred_rel_turnout) %>%
    mutate(pred_participation = case_when(pred_participation > 0.9 ~ 0.9,
                                          pred_participation < 0.61 ~ 0.61,
                                          T ~ pred_participation))
}

# District Simulation -----------------------------------------------------------------------------------------------

# District result = simulated national result + simulated regional swing; votes = share * eligible * turnout
sim_bezirk <- function(set_GKZ, regional_data, district_correlation_matrices, eligible_voters,
                       national_results, turnout_prediction, n_simulations = 10^4){
  bezirksinfos <- regional_data %>%
    filter(GKZ == set_GKZ) %>%
    distinct(GKZ, Gebietsname, state)

  bezirksdaten <- regional_data %>%
    filter(GKZ == set_GKZ) %>%
    left_join(party_order, by = "party") %>% arrange(order) %>% select(-order)

  swing_avg <- bezirksdaten %>% pull(reg_swing_avg)
  std_dev <- bezirksdaten %>% pull(reg_swing_sd)

  bezirksmatrix <- district_correlation_matrices[[bezirksinfos$Gebietsname]]
  cov_matrix <- diag(std_dev) %*% bezirksmatrix %*% diag(std_dev)

  set.seed(123)
  simulated_data <- MASS::mvrnorm(n = n_simulations, mu = swing_avg, Sigma = cov_matrix)

  simulated_data %>%
    as.data.frame() %>%
    setNames(party_order$party) %>%
    mutate(sim_id = row_number()) %>%
    mutate(GKZ = set_GKZ,
           state = bezirksinfos$state,
           Gebietsname = bezirksinfos$Gebietsname) %>%
    left_join(turnout_prediction %>% select(sim_id, GKZ, pred_participation),
              by = join_by(sim_id, GKZ)) %>%
    left_join(eligible_voters, by = "GKZ") %>%
    mutate(pred_voters = eligible_voters * pred_participation) %>%
    pivot_longer(cols = c(ÖVP:KEINE), names_to = "party", values_to = "reg_swing_result") %>%
    left_join(national_results %>% select(sim_id, party, nat_result = result),
              by = join_by(sim_id, party)) %>%
    mutate(result = nat_result + reg_swing_result) %>%
    mutate(result = ifelse(result < 0.0001, 0.0001, result)) %>%
    mutate(pred_votes = round(result * pred_voters))
}

# Seat Allocation ---------------------------------------------------------------------------------------------------

# Hands out each simulation's remaining seats one at a time to the party with the highest votes / (seats + 1).
# Same rule as the original implementation (on an exact tie every tied party gets a seat), written per simulation
# in base R instead of re-filtering the full data frame for every seat.
dhondt_method <- function(results, remaining_seats) {
  results <- results %>% arrange(sim_id)
  open <- remaining_seats$seats_open[match(unique(results$sim_id), remaining_seats$sim_id)]

  idx <- split(seq_len(nrow(results)), results$sim_id)
  seats <- results$seats_given
  votes <- results$pred_votes

  for(j in seq_along(idx)){
    rows <- idx[[j]]
    s <- seats[rows]
    v <- votes[rows]
    for(k in seq_len(max(open[j], 0))){
      d <- v / (s + 1)
      winners <- which(d == max(d))
      s[winners] <- s[winners] + 1
    }
    seats[rows] <- s
  }

  results$seats_given <- seats
  results
}
