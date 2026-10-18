
# Simulates the election n_sims times:
#   national vote (polls) -> district turnout -> district vote shares (national + regional swing) -> aggregate
# Output: output/sims_votes.rds (district, state and national results per simulation; gitignored, ~100 MB in memory)

load("model/correlations.Rda")
load("model/turnout.Rda")
regional_data <- read_csv2("model/regional_data.csv", show_col_types = F)
election_results <- get_election_results()

# Polls -------------------------------------------------------------------------------------------------------------

polls_adj <- get_polling_data(as_of = FORECAST_DATE)
polling_average <- summarise_polls(polls_adj)
write_csv(polling_average, "output/polling_average.csv")

# National vote + turnout -------------------------------------------------------------------------------------------

nat_sim <- sim_national_vote(polls_adj, nat_correlation_matrix, n_simulations = n_sims)

pred_turnout <- sim_turnout(regional_turnout, turnout_correlation_matrix, pred_nat_turnout, pred_nat_turnout_sd,
                            n_simulations = n_sims)

# Districts ---------------------------------------------------------------------------------------------------------

# Electorate size per district taken from the most recent election (EU 2024)
eligible_voters <- election_results %>%
  filter(type == "EU", year == 2024) %>%
  select(GKZ, eligible_voters = Wahlberechtigte)

districts <- regional_data %>%
  filter(category == "Wahlbezirk") %>%
  distinct(GKZ, Gebietsname, state)

bezirk_sim <- map(districts$GKZ, \(g) sim_bezirk(set_GKZ = g,
                                                 regional_data = regional_data,
                                                 district_correlation_matrices = district_correlation_matrices,
                                                 eligible_voters = eligible_voters,
                                                 national_results = nat_sim,
                                                 turnout_prediction = pred_turnout,
                                                 n_simulations = n_sims),
                  .progress = "Simulating districts") %>%
  list_rbind()

stopifnot(nrow(bezirk_sim) == nrow(districts) * n_sims * length(parties_2024))

# Aggregate to states and nation ------------------------------------------------------------------------------------

state_turnout <- bezirk_sim %>%
  distinct(sim_id, GKZ, state, pred_voters, eligible_voters) %>%
  group_by(sim_id, state) %>%
  summarise(pred_voters = sum(pred_voters, na.rm = T),
            eligible_voters = sum(eligible_voters),
            .groups = "drop") %>%
  mutate(pred_participation = pred_voters / eligible_voters)

state_sim <- bezirk_sim %>%
  group_by(sim_id, state, party) %>%
  summarise(pred_votes = sum(pred_votes, na.rm = T), .groups = "drop") %>%
  left_join(regional_data %>%
              filter(category == "Bundesland") %>%
              distinct(GKZ, state, Gebietsname),
            by = "state") %>%
  left_join(state_turnout, by = join_by(sim_id, state)) %>%
  mutate(result = pred_votes / pred_voters) %>%
  select(sim_id, GKZ, Gebietsname, state, everything())

national_turnout <- bezirk_sim %>%
  distinct(sim_id, GKZ, pred_voters, eligible_voters) %>%
  group_by(sim_id) %>%
  summarise(pred_voters = sum(pred_voters, na.rm = T),
            eligible_voters = sum(eligible_voters),
            .groups = "drop") %>%
  mutate(pred_participation = pred_voters / eligible_voters)

national_sim <- bezirk_sim %>%
  group_by(sim_id, party) %>%
  summarise(pred_votes = sum(pred_votes, na.rm = T), .groups = "drop") %>%
  left_join(national_turnout, by = join_by(sim_id)) %>%
  mutate(result = pred_votes / pred_voters) %>%
  select(sim_id, everything())

saveRDS(list(bezirk_sim = bezirk_sim, state_sim = state_sim, national_sim = national_sim),
        "output/sims_votes.rds")
