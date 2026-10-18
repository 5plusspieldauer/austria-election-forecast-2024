
# Figures for the model explainer (MODEL.md): turnout, polls, correlations, regional swing, simulated results
# Reads: output/polling_average.csv, output/sims_votes.rds, model/, data/

source("R/plot_helpers.R")

election_results <- get_election_results()
load("model/correlations.Rda")
rwk <- read_rwk_shapes()
national_sim <- readRDS("output/sims_votes.rds")$national_sim

main_parties <- c("ÖVP", "SPÖ", "FPÖ", "GRÜNE", "NEOS", "KPÖ", "BIER")

# Polling average ---------------------------------------------------------------------------------------------------

p_polls <- read_csv("output/polling_average.csv", show_col_types = F) %>%
  filter(party %in% main_parties) %>%
  mutate(party = factor(party, levels = main_parties)) %>%
  ggplot(aes(x = party, y = polling_avg, fill = party)) +
  geom_col(width = 0.7) +
  geom_errorbar(aes(ymin = polling_avg - moe, ymax = polling_avg + moe), width = 0.2, colour = "grey30") +
  geom_text(aes(y = polling_avg + moe + 0.012, label = scales::label_percent(0.1)(polling_avg)), size = 3.5) +
  geom_hline(yintercept = 0.04, linetype = "dashed", colour = "grey40") +
  annotate("text", x = 0.45, y = 0.047, label = "4% threshold", hjust = 0, size = 3, colour = "grey40") +
  scale_fill_manual(values = color_palette, guide = "none") +
  scale_x_discrete(labels = party_labels) +
  scale_y_continuous(labels = scales::label_percent(), expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Weighted polling average, 27 September 2024",
       subtitle = "Polls weighted by survey method and recency; bars show the weighted margin of error",
       x = NULL, y = NULL, caption = "Polls: @Wahlen_AT poll collection") +
  theme_forecast() +
  theme(panel.grid.major.x = element_blank())
save_fig(p_polls, "polling_average.png")

# National simulation -----------------------------------------------------------------------------------------------

p_national <- national_sim %>%
  filter(party %in% main_parties) %>%
  mutate(party = factor(party, levels = main_parties)) %>%
  ggplot(aes(x = result, fill = party, colour = party)) +
  geom_density(alpha = 0.35, adjust = 1.2) +
  geom_vline(xintercept = 0.04, linetype = "dashed", colour = "grey40") +
  scale_fill_manual(values = color_palette, labels = party_labels, name = NULL) +
  scale_colour_manual(values = color_palette, labels = party_labels, name = NULL) +
  scale_x_continuous(labels = scales::label_percent()) +
  labs(title = "Simulated national vote share",
       subtitle = "10,000 simulations, aggregated from the 39 regional electoral districts",
       x = NULL, y = NULL) +
  theme_forecast() +
  theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank(), legend.position = "top")
save_fig(p_national, "national_vote_simulation.png")

# Independent vs. correlated simulation -----------------------------------------------------------------------------

# Why correlate? ÖVP vs. FPÖ drawn independently vs. with the national correlation matrix.
# Raw draws without the vote-share floors, same means and SDs for both versions.
polling_average <- read_csv("output/polling_average.csv", show_col_types = F)
n_scatter <- 3000
idx <- match(c("ÖVP", "FPÖ"), polling_average$party)
r_ovp_fpo <- nat_correlation_matrix["ÖVP", "FPÖ"]

set.seed(1)
draws_independent <- sapply(polling_average$moe, \(s) rnorm(n_scatter, 0, s))
set.seed(1)
draws_correlated <- MASS::mvrnorm(n_scatter, rep(0, nrow(polling_average)),
                                  diag(polling_average$moe) %*% nat_correlation_matrix %*% diag(polling_average$moe))

correlated_label <- paste0("Correlated (r = ", sub("-", "−", sprintf("%.2f", r_ovp_fpo)), ")")
scatter_draws <- bind_rows(
  tibble(version = "Independent", ovp = draws_independent[, idx[1]], fpo = draws_independent[, idx[2]]),
  tibble(version = correlated_label, ovp = draws_correlated[, idx[1]], fpo = draws_correlated[, idx[2]])
) %>%
  mutate(ovp = ovp + polling_average$polling_avg[idx[1]],
         fpo = fpo + polling_average$polling_avg[idx[2]],
         version = factor(version, levels = c("Independent", correlated_label)))

p_scatter <- scatter_draws %>%
  ggplot(aes(ovp, fpo)) +
  geom_point(alpha = 0.25, size = 0.8, colour = "#2e5f8a") +
  facet_wrap(~ version) +
  scale_x_continuous(labels = scales::label_percent()) +
  scale_y_continuous(labels = scales::label_percent()) +
  coord_equal() +
  labs(title = paste0("ÖVP vs. FPÖ in ", scales::label_comma()(n_scatter), " simulated elections"),
       subtitle = "Correlated draws: when ÖVP does better than its polls, FPÖ tends to do worse",
       x = "ÖVP", y = "FPÖ") +
  theme_forecast() +
  theme(strip.text = element_text(face = "bold", size = 11))
save_fig(p_scatter, "independent_vs_correlated.png", width = 8, height = 4.4)

# Party correlation heatmaps ----------------------------------------------------------------------------------------

cor_heatmap_data <- function(m, label){
  m[1:6, 1:6] %>%
    as_tibble(rownames = "party_a") %>%
    pivot_longer(-party_a, names_to = "party_b", values_to = "correlation") %>%
    mutate(across(c(party_a, party_b), ~ factor(.x, levels = parties_2024[1:6])),
           panel = label)
}

cor_heatmap <- function(data){
  data %>%
    ggplot(aes(party_b, fct_rev(party_a), fill = correlation)) +
    geom_tile(colour = "white") +
    geom_text(aes(label = sprintf("%.2f", correlation)), size = 3.3) +
    scale_fill_distiller(palette = "RdBu", direction = 1, limits = c(-1, 1), guide = "none") +
    scale_x_discrete(labels = party_labels, position = "top") +
    scale_y_discrete(labels = party_labels) +
    coord_fixed() +
    theme_forecast() +
    theme(panel.grid = element_blank())
}

p_cor <- cor_heatmap(cor_heatmap_data(nat_correlation_matrix, "National")) +
  labs(title = "Correlation between national vote shares", x = NULL, y = NULL,
       caption = "National Council and EU elections")
save_fig(p_cor, "national_correlations.png", width = 6, height = 5.5)

p_cor_regional <- bind_rows(
  cor_heatmap_data(district_correlation_matrices[["Innsbruck"]], "Innsbruck"),
  cor_heatmap_data(district_correlation_matrices[["Graz und Umgebung"]], "Graz und Umgebung")
) %>%
  mutate(panel = factor(panel, levels = c("Innsbruck", "Graz und Umgebung"))) %>%
  cor_heatmap() +
  facet_wrap(~ panel) +
  labs(title = "Correlation between parties' regional swings",
       subtitle = "Computed across elections since 2013, separately for every regional electoral district",
       x = NULL, y = NULL) +
  theme(strip.text = element_text(face = "bold", size = 11))
save_fig(p_cor_regional, "regional_correlations.png", width = 10, height = 5.4)

# Regional swing ----------------------------------------------------------------------------------------------------

swing_map <- function(party_code, election_type = "EU", election_year = 2024, limit = 0.15){
  swing <- calc_regional_swing_long(election_results, categories = "Wahlbezirk") %>%
    filter(party == party_code, type == election_type, year == election_year)
  nat <- swing$nat_pct[1]

  rwk %>%
    left_join(swing, by = "GKZ") %>%
    ggplot() +
    geom_sf(aes(fill = reg_swing), colour = "white", linewidth = 0.2) +
    scale_fill_gradient2(low = "#6a51a3", mid = "grey96", high = color_palette[[party_code]],
                         limits = c(-limit, limit), labels = scales::label_percent(),
                         name = "vs. national\nresult") +
    labs(title = paste0(party_labels[[party_code]], ": regional swing, ",
                        ifelse(election_type == "EU", "EU election ", "National Council "), election_year),
         subtitle = paste0("District result minus national result (", scales::label_percent(0.1)(nat), ")")) +
    theme_map()
}

p_swing <- patchwork::wrap_plots(swing_map("SPÖ", limit = 0.12), swing_map("ÖVP"), ncol = 1)
save_fig(p_swing, "regional_swing_spo_ovp.png", width = 8, height = 7.5)

# Worked example for the explainer: SPÖ in Innsbruck
swing_weights <- tibble(year = c(2024, 2019, 2017, 2014, 2013), weight = c(1, 0.67, 0.4, 0.2, 0.2))
swing_example <- calc_regional_swing_long(election_results, categories = "Wahlbezirk") %>%
  filter(GKZ == "G7A000", party == "SPÖ", year >= 2013) %>%
  inner_join(swing_weights, by = "year") %>%
  select(Gebietsname, type, year, party, pct, nat_pct, reg_swing, weight) %>%
  arrange(desc(year), type)
stopifnot(nrow(swing_example) == 6)
write_csv(swing_example, "output/swing_example_spo_innsbruck.csv")

# Turnout -----------------------------------------------------------------------------------------------------------

relative_turnout <- election_results %>%
  filter(category == "Wahlbezirk", !grepl("Wahlkarten", Gebietsname), year >= 2013) %>%
  left_join(election_results %>%
              filter(category == "Bund") %>%
              select(type, year, nat_participation = participation),
            by = join_by(type, year)) %>%
  mutate(rel_participation = participation - nat_participation,
         election = paste0(ifelse(type == "NR", "National Council ", "EU Parliament "), year,
                           "\n(turnout ", scales::label_percent(0.1)(nat_participation), ")"))

election_levels <- relative_turnout %>% distinct(year, type, election) %>% arrange(desc(year), desc(type)) %>% pull(election)

p_turnout <- rwk %>%
  inner_join(relative_turnout %>% select(GKZ, election, rel_participation), by = "GKZ", relationship = "one-to-many") %>%
  mutate(election = factor(election, levels = election_levels)) %>%
  ggplot() +
  geom_sf(aes(fill = rel_participation), colour = "white", linewidth = 0.1) +
  facet_wrap(~ election, ncol = 3) +
  scale_fill_distiller(palette = "RdBu", direction = 1, limits = c(-0.15, 0.15), oob = scales::squish,
                       labels = scales::label_number(1, scale = 100, style_positive = "plus", suffix = " pts"),
                       name = "Turnout vs.\nnational") +
  labs(title = "Turnout relative to the national figure",
       subtitle = "By regional electoral district, elections since 2013") +
  theme_map(base_size = 11) +
  theme(strip.text = element_text(size = 10, margin = margin(b = 3)),
        plot.subtitle = element_text(hjust = 0.5, margin = margin(b = 8)))
save_fig(p_turnout, "relative_turnout.png", width = 10, height = 5.2)

turnout_cor <- function(gkz, label){
  rwk %>%
    left_join(tibble(GKZ = colnames(turnout_correlation_matrix),
                     correlation = turnout_correlation_matrix[gkz, ]), by = "GKZ") %>%
    mutate(panel = label, focus = GKZ == gkz)
}

p_turnout_cor <- bind_rows(turnout_cor("G7A000", "Innsbruck"),
                           turnout_cor("G7B000", "Innsbruck-Land")) %>%
  mutate(panel = factor(panel, levels = c("Innsbruck", "Innsbruck-Land"))) %>%
  ggplot() +
  geom_sf(aes(fill = correlation), colour = "white", linewidth = 0.15) +
  geom_sf(data = \(d) filter(d, focus), fill = NA, colour = "black", linewidth = 0.6) +
  facet_wrap(~ panel, ncol = 1) +
  scale_fill_distiller(palette = "RdBu", direction = 1, limits = c(-1, 1), name = "Correlation") +
  labs(title = "Which districts' turnout moves together?",
       subtitle = "Correlation of relative turnout with the outlined district") +
  theme_map() +
  theme(strip.text = element_text(face = "bold", size = 11, margin = margin(b = 3)),
        plot.subtitle = element_text(hjust = 0.5, margin = margin(b = 10)))
save_fig(p_turnout_cor, "turnout_correlation_innsbruck.png", width = 8, height = 7.5)

# Results: Tirol's districts ----------------------------------------------------------------------------------------

bezirk_sim <- readRDS("output/sims_votes.rds")$bezirk_sim

p_tirol <- bezirk_sim %>%
  filter(state == "Tirol", party %in% main_parties) %>%
  mutate(party = factor(party, levels = main_parties)) %>%
  ggplot(aes(x = result, fill = party, colour = party)) +
  geom_density(alpha = 0.35, adjust = 1.2) +
  facet_wrap(~ Gebietsname, nrow = 2) +
  scale_fill_manual(values = color_palette, labels = party_labels, name = NULL) +
  scale_colour_manual(values = color_palette, labels = party_labels, name = NULL) +
  scale_x_continuous(labels = scales::label_percent()) +
  labs(title = "Simulated results in Tirol's five regional electoral districts",
       subtitle = "10,000 simulations",
       x = NULL, y = NULL) +
  theme_forecast(base_size = 11) +
  theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank(), legend.position = "top",
        strip.text = element_text(face = "bold"))
save_fig(p_tirol, "tirol_districts.png", width = 9, height = 5)

# Results: seats ----------------------------------------------------------------------------------------------------

p_seats <- read_csv("output/seat_distribution.csv", show_col_types = F) %>%
  filter(party %in% main_parties) %>%
  mutate(party = factor(party, levels = main_parties)) %>%
  ggplot(aes(x = seats, y = n_sims / sum(n_sims[party == "FPÖ"]), fill = party)) +
  geom_col(width = 1, alpha = 0.85) +
  facet_wrap(~ party, nrow = 2, scales = "free", labeller = as_labeller(party_labels)) +
  scale_fill_manual(values = color_palette, guide = "none") +
  scale_x_continuous(breaks = \(x) keep(scales::breaks_pretty()(x), \(b) b == round(b))) +
  scale_y_continuous(labels = scales::label_percent()) +
  labs(title = "Simulated seats in the National Council",
       subtitle = "Share of simulations ending with each seat count",
       x = "Seats", y = NULL) +
  theme_forecast(base_size = 11)
save_fig(p_seats, "seat_distribution.png", width = 9, height = 5)
