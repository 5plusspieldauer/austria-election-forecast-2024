
# Estimates the model inputs from past election results:
#   - regional swing (mean + SD) per party and electoral district / state
#   - party correlation matrices (national, per state, per district)
#   - turnout: predicted national turnout and each district's relative turnout, plus their correlations
# Output: model/regional_data.csv, model/turnout.Rda, model/correlations.Rda

election_results <- get_election_results()

# Regional Swing ----------------------------------------------------------------------------------------------------

# Electoral districts were redrawn for 2013, so only 2013+ elections get a weight
regional_swing_recency_weights <- tibble(year = c(2024, 2019, 2017, 2014, 2013),
                                         t_weight = c(1, 0.67, 0.4, 0.2, 0.2))

swing_long <- calc_regional_swing_long(election_results, categories = c("Bundesland", "Wahlbezirk"))

regional_swing <- swing_long %>%
  left_join(regional_swing_recency_weights, by = "year") %>%
  group_by(GKZ, category, Gebietsname, state, party) %>%
  summarise(reg_swing_avg = weighted.mean(reg_swing, t_weight, na.rm = T), .groups = "drop")

regional_swing_sd <- swing_long %>%
  group_by(GKZ, category, Gebietsname, state, party) %>%
  summarise(reg_swing_sd = sd(reg_swing, na.rm = T), .groups = "drop")

# New parties (LMP, KEINE) get zero swing with a small SD; BIER (one prior result) gets a default SD
areas <- regional_swing %>% distinct(GKZ, category, Gebietsname, state)

regional_data <- bind_rows(
  regional_swing %>%
    filter(party %in% parties_2024) %>%
    left_join(regional_swing_sd, by = join_by(GKZ, category, Gebietsname, state, party)) %>%
    mutate(reg_swing_sd = replace_na(reg_swing_sd, 0.003)),
  areas %>% mutate(party = "LMP",   reg_swing_avg = 0, reg_swing_sd = 0.002),
  areas %>% mutate(party = "KEINE", reg_swing_avg = 0, reg_swing_sd = 0.002)
) %>%
  arrange(GKZ)

write_csv2(regional_data, file = "model/regional_data.csv")

# Turnout -----------------------------------------------------------------------------------------------------------

turnout_recency_weights <- tibble(year = c(2024, 2019, 2017, 2014, 2013, 2008, 2006, 2002),
                                  t_weight = c(1, 0.67, 0.4, 0.2, 0.2, 0.1, 0.1, 0.1))

national_nr_turnout <- election_results %>%
  filter(category == "Bund", type == "NR") %>%
  select(type, year, participation) %>%
  left_join(turnout_recency_weights, by = "year")

pred_nat_turnout <- weighted.mean(national_nr_turnout$participation, national_nr_turnout$t_weight, na.rm = T)
pred_nat_turnout_sd <- sd(national_nr_turnout$participation, na.rm = T)

rel_turnout_long <- election_results %>%
  filter(!grepl("Wahlkarten", Gebietsname)) %>%
  filter(year > 2008) %>%
  filter(category == "Wahlbezirk") %>%
  left_join(election_results %>%
              filter(category == "Bund") %>%
              select(type, year, nat_participation = participation),
            by = join_by(type, year)) %>%
  select(year, type, GKZ, category, Gebietsname, state, participation, nat_participation) %>%
  mutate(rel_participation = participation - nat_participation)

regional_turnout <- rel_turnout_long %>%
  left_join(turnout_recency_weights, by = "year") %>%
  group_by(GKZ, category, Gebietsname, state) %>%
  summarise(rel_participation_sd = sd(rel_participation, na.rm = T),
            rel_participation = weighted.mean(rel_participation, t_weight, na.rm = T),
            .groups = "drop")

save(regional_turnout, pred_nat_turnout, pred_nat_turnout_sd, file = "model/turnout.Rda")

# Correlation Matrices ----------------------------------------------------------------------------------------------

# Correlations between parties' regional swings, computed per area across elections
swing_correlations <- function(category){
  swing_wide <- calc_regional_swing_long(election_results, categories = category, fill_national_na = TRUE) %>%
    filter(party %in% parties_2024) %>%
    filter(!party %in% c("BIER", "LMP", "KEINE")) %>%
    select(year, type, Gebietsname, party, reg_swing) %>%
    pivot_wider(names_from = "party", values_from = "reg_swing") %>%
    select(-c(year, type))

  m <- by(swing_wide[, -1], swing_wide$Gebietsname, cor)
  for(i in seq_along(m)) m[[i]] <- pad_minor_parties(m[[i]])
  m
}

state_correlation_matrices <- swing_correlations("Bundesland")
district_correlation_matrices <- swing_correlations("Wahlbezirk")

# National: correlations between parties' national vote shares across elections
nat_correlation_matrix <- election_results %>%
  mutate(across(c(ÖVP:BIER), ~ replace_na(.x/Stimmen_g, 0))) %>%
  filter(category == "Bund") %>%
  pivot_longer(cols = c(ÖVP:BIER), names_to = "party", values_to = "votes") %>%
  filter(party %in% parties_2024) %>%
  filter(!party %in% c("BIER", "LMP", "KEINE")) %>%
  select(year, type, Gebietsname, party, votes) %>%
  pivot_wider(names_from = "party", values_from = "votes") %>%
  select(-c(year, type, Gebietsname)) %>%
  cor() %>%
  pad_minor_parties()

# Turnout: correlations between districts' relative turnout across elections
turnout_correlation_matrix <- rel_turnout_long %>%
  select(year, type, GKZ, rel_participation) %>%
  arrange(GKZ) %>%
  pivot_wider(names_from = "GKZ", values_from = "rel_participation") %>%
  select(-c(year, type)) %>%
  cor()

save(nat_correlation_matrix, state_correlation_matrices, district_correlation_matrices, turnout_correlation_matrix,
     file = "model/correlations.Rda")
