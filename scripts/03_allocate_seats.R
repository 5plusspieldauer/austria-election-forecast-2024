
# Turns each simulated vote into a 183-seat National Council, following the Nationalrats-Wahlordnung:
#   1. regional districts: seats = floor(votes / state quota)        ("Grundmandate", direct seats)
#   2. states: parties with a direct seat OR >= 4% nationally get floor(state votes / state quota) seats
#   3. federal: remaining seats up to 183 distributed by D'Hondt
# Output: output/sims_seats.rds (gitignored) + small summary CSVs in output/

sims <- readRDS("output/sims_votes.rds")
bezirk_sim <- sims$bezirk_sim
state_sim <- sims$state_sim
national_sim <- sims$national_sim
rm(sims)

# State quota (Wahlzahl) --------------------------------------------------------------------------------------------

seats_by_state <- read_csv2("data/misc/seats_by_region.csv", show_col_types = F) %>%
  filter(grepl("0000", GKZ)) %>%
  select(state = Bezeichnung, seat_alloc = Mandate)

threshold_by_state <- state_sim %>%
  distinct(sim_id, state, pred_voters) %>%
  left_join(seats_by_state, by = "state") %>%
  mutate(vote_threshold = round(pred_voters / seat_alloc, 0)) %>%
  distinct(sim_id, state, vote_threshold)

# Round 1: direct seats in the regional districts -------------------------------------------------------------------

first_round_results <- bezirk_sim %>%
  left_join(threshold_by_state, by = join_by(sim_id, state)) %>%
  mutate(seats = floor(pred_votes / vote_threshold)) %>%
  group_by(sim_id, state, party) %>%
  summarise(seats = sum(seats), .groups = "drop")

parties_with_direct_mandates <- first_round_results %>%
  filter(seats > 0) %>%
  distinct(sim_id, party)

parties_above_four_pct <- national_sim %>%
  filter(result > 0.04) %>%
  distinct(sim_id, party)

parties_in_rd_2 <- bind_rows(parties_with_direct_mandates, parties_above_four_pct) %>%
  distinct(sim_id, party)

# Round 2: state seats ----------------------------------------------------------------------------------------------

second_round_results <- state_sim %>%
  inner_join(parties_in_rd_2, by = join_by(party, sim_id)) %>%
  left_join(threshold_by_state, by = join_by(sim_id, state)) %>%
  mutate(seats = floor(pred_votes / vote_threshold)) %>%
  group_by(sim_id, GKZ, Gebietsname, state, party) %>%
  summarise(seats = sum(seats), .groups = "drop") %>%
  left_join(first_round_results %>% select(sim_id, state, party, first_round_seats = seats),
            by = join_by(sim_id, state, party)) %>%
  mutate(second_round_seats = seats - first_round_seats) %>%
  group_by(sim_id, party) %>%
  summarise(seats_given = sum(first_round_seats + second_round_seats), .groups = "drop") %>%
  left_join(national_sim %>% select(sim_id, party, pred_votes), by = join_by(sim_id, party))

seats_open <- second_round_results %>%
  group_by(sim_id) %>%
  summarise(seats_given = sum(seats_given)) %>%
  mutate(seats_open = 183 - seats_given)

# Round 3: D'Hondt at the federal level -----------------------------------------------------------------------------

seat_results <- dhondt_method(second_round_results, seats_open)

saveRDS(seat_results, "output/sims_seats.rds")

# Summaries (small, committed) --------------------------------------------------------------------------------------

# parties that miss parliament in a simulation have no row -> fill with 0 seats
seats_full <- seat_results %>%
  select(sim_id, party, seats = seats_given) %>%
  complete(sim_id = unique(national_sim$sim_id), party = parties_2024, fill = list(seats = 0))

forecast_summary <- national_sim %>%
  group_by(party) %>%
  summarise(vote_median = median(result),
            vote_q05 = quantile(result, 0.05),
            vote_q95 = quantile(result, 0.95)) %>%
  left_join(seats_full %>%
              group_by(party) %>%
              summarise(p_in_parliament = mean(seats > 0),
                        seats_mean = mean(seats),
                        seats_median = median(seats),
                        seats_q05 = quantile(seats, 0.05),
                        seats_q95 = quantile(seats, 0.95)),
            by = "party") %>%
  left_join(party_order, by = "party") %>% arrange(order) %>% select(-order)

write_csv(forecast_summary, "output/forecast_summary.csv")
write_csv(seats_full %>% count(party, seats, name = "n_sims"), "output/seat_distribution.csv")

coalitions <- list("FPÖ + ÖVP"          = c("FPÖ", "ÖVP"),
                   "ÖVP + SPÖ"          = c("ÖVP", "SPÖ"),
                   "ÖVP + SPÖ + NEOS"   = c("ÖVP", "SPÖ", "NEOS"),
                   "ÖVP + SPÖ + GRÜNE"  = c("ÖVP", "SPÖ", "GRÜNE"),
                   "ÖVP + GRÜNE + NEOS" = c("ÖVP", "GRÜNE", "NEOS"),
                   "SPÖ + GRÜNE + NEOS" = c("SPÖ", "GRÜNE", "NEOS"),
                   "ÖVP + GRÜNE"        = c("ÖVP", "GRÜNE"),
                   "ÖVP + NEOS"         = c("ÖVP", "NEOS"))

coalition_odds <- imap(coalitions, \(parties, name) seats_full %>%
                         filter(party %in% parties) %>%
                         group_by(sim_id) %>%
                         summarise(seats = sum(seats)) %>%
                         summarise(coalition = name,
                                   seats_median = median(seats),
                                   p_majority = mean(seats >= 92))) %>%
  list_rbind()

write_csv(coalition_odds, "output/coalition_odds.csv")

seat_totals <- seats_full %>% group_by(sim_id) %>% summarise(total = sum(seats))
message("Seat totals across simulations: ", paste(names(table(seat_totals$total)), table(seat_totals$total),
                                                  sep = " seats x", collapse = ", "))
