
# Compares the final forecast (2024-09-27) with the official result of the 2024-09-29 election.
# Reads: output/forecast_summary.csv, output/seat_distribution.csv, output/sims_votes.rds,
#        data/election_results/NR2024.csv (official BMI result), data/misc/seats_2024.csv

source("R/plot_helpers.R")

nr2024 <- read_csv2("data/election_results/NR2024.csv", show_col_types = F)
national_2024 <- nr2024 %>% filter(GKZ == "G00000")

# shares of valid votes, like the model
actual <- national_2024 %>%
  pivot_longer(all_of(parties_2024), names_to = "party", values_to = "votes") %>%
  transmute(party, votes, share = votes / Stimmen_g) %>%
  inner_join(read_csv("data/misc/seats_2024.csv", show_col_types = F), by = "party")
stopifnot(nrow(actual) == length(parties_2024), sum(actual$seats) == 183)

# the model's turnout is valid votes / eligible voters (invalid ballots excluded)
actual_turnout <- national_2024$Stimmen_g / national_2024$Wahlberechtigte

forecast <- read_csv("output/forecast_summary.csv", show_col_types = F)
seat_dist <- read_csv("output/seat_distribution.csv", show_col_types = F)
national_sim <- readRDS("output/sims_votes.rds")$national_sim

main_parties <- c("FPÖ", "ÖVP", "SPÖ", "NEOS", "GRÜNE", "KPÖ", "BIER")

# Table -------------------------------------------------------------------------------------------------------------

# Where in the forecast distribution did the actual result land? (share of simulations below the actual result)
percentile <- national_sim %>%
  inner_join(actual %>% select(party, actual_share = share), by = "party") %>%
  group_by(party) %>%
  summarise(actual_percentile = mean(result < actual_share))

postmortem <- forecast %>%
  inner_join(actual %>% select(party, actual_share = share, actual_seats = seats), by = "party") %>%
  left_join(percentile, by = "party") %>%
  mutate(vote_error = vote_median - actual_share,
         seat_error = seats_median - actual_seats,
         inside_90 = actual_share >= vote_q05 & actual_share <= vote_q95)

write_csv(postmortem, "output/postmortem.csv")

turnout_q <- quantile(distinct(national_sim, sim_id, pred_participation)$pred_participation, c(0.05, 0.5, 0.95))
message("Turnout: forecast ", paste(scales::label_percent(0.1)(turnout_q), collapse = " / "),
        " (5/50/95%), actual ", scales::label_percent(0.1)(actual_turnout))

# Vote share: forecast interval vs result ---------------------------------------------------------------------------

p_votes <- postmortem %>%
  filter(party %in% main_parties) %>%
  mutate(party = factor(party, levels = rev(main_parties))) %>%
  ggplot(aes(y = party)) +
  geom_vline(xintercept = 0.04, linetype = "dashed", colour = "grey60") +
  geom_linerange(aes(xmin = vote_q05, xmax = vote_q95, colour = party), linewidth = 6, alpha = 0.35) +
  geom_point(aes(x = vote_median, colour = party), size = 3) +
  geom_point(aes(x = actual_share), shape = 4, size = 3.5, stroke = 1.4) +
  geom_text(aes(x = pmax(vote_q95, actual_share) + 0.008,
                label = paste0(scales::label_number(0.1, scale = 100, style_positive = "plus")(-vote_error), " pts")),
            hjust = 0, size = 3.3, colour = "grey30") +
  scale_colour_manual(values = color_palette, guide = "none") +
  scale_y_discrete(labels = party_labels) +
  scale_x_continuous(labels = scales::label_percent(), limits = c(0, 0.345)) +
  labs(title = "Forecast vs. result: vote share",
       subtitle = "Bar: 90% forecast interval  ·  dot: forecast median  ·  ✕: actual result  ·  label: result minus forecast",
       x = NULL, y = NULL,
       caption = "Forecast of 27 Sep 2024 (10,000 simulations). Result: BMI, 29 Sep 2024") +
  theme_forecast() +
  theme(panel.grid.major.y = element_blank())
save_fig(p_votes, "postmortem_votes.png", width = 8.5, height = 4.5)

# Seats: forecast distribution vs result ----------------------------------------------------------------------------

p_seats <- seat_dist %>%
  filter(party %in% main_parties) %>%
  mutate(party = factor(party, levels = main_parties)) %>%
  ggplot(aes(x = seats, y = n_sims / 10^4, fill = party)) +
  geom_col(width = 1, alpha = 0.8) +
  geom_vline(data = actual %>% filter(party %in% main_parties) %>%
               mutate(party = factor(party, levels = main_parties)),
             aes(xintercept = seats), linewidth = 0.8) +
  facet_wrap(~ party, nrow = 2, scales = "free", labeller = as_labeller(party_labels)) +
  scale_fill_manual(values = color_palette, guide = "none") +
  scale_x_continuous(breaks = \(x) keep(scales::breaks_pretty()(x), \(b) b == round(b))) +
  scale_y_continuous(labels = scales::label_percent()) +
  labs(title = "Forecast vs. result: seats",
       subtitle = "Share of simulations ending with each seat count; black line = seats actually won",
       x = "Seats", y = NULL) +
  theme_forecast(base_size = 11)
save_fig(p_seats, "postmortem_seats.png", width = 9, height = 5)

# Hemicycles: median forecast vs result -----------------------------------------------------------------------------

# left-to-right seating order
hemi_order <- c("KPÖ", "GRÜNE", "SPÖ", "BIER", "NEOS", "ÖVP", "FPÖ")

# largest-remainder rounding of mean seats, so the illustrative forecast chamber sums to 183
mean_seats <- forecast %>% filter(seats_mean > 0) %>% select(party, seats_mean)
hemi_forecast <- mean_seats %>%
  mutate(seats = floor(seats_mean),
         rem = seats_mean - seats) %>%
  arrange(desc(rem)) %>%
  mutate(seats = seats + (row_number() <= 183 - sum(seats))) %>%
  select(party, seats)
stopifnot(sum(hemi_forecast$seats) == 183)

hemi <- bind_rows(
  hemicycle_data(hemi_forecast, hemi_order) %>% mutate(panel = "Forecast (average of simulations)"),
  hemicycle_data(actual %>% select(party, seats), hemi_order) %>% mutate(panel = "Result")
)

hemi_labels <- bind_rows(hemi_forecast %>% filter(seats > 0) %>% mutate(panel = "Forecast (average of simulations)"),
                         actual %>% filter(seats > 0) %>% select(party, seats) %>% mutate(panel = "Result")) %>%
  mutate(party = factor(party, levels = hemi_order)) %>%
  arrange(panel, party) %>%
  group_by(panel) %>%
  summarise(label = paste0(party_labels[as.character(party)], " ", seats, collapse = "  ·  "))

p_hemi <- hemi %>%
  ggplot(aes(x, y, colour = party)) +
  geom_point(size = 2.6) +
  geom_text(data = hemi_labels, aes(x = 0, y = -0.35, label = label), inherit.aes = FALSE, size = 3.2) +
  annotate("text", x = 0, y = 0.2, label = "92 for a majority", size = 3, colour = "grey40") +
  facet_wrap(~ panel) +
  scale_colour_manual(values = color_palette, guide = "none") +
  coord_fixed(ylim = c(-0.5, 2.3)) +
  labs(title = "Austria's National Council, 183 seats") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold", hjust = 0.5),
        strip.text = element_text(size = 12, margin = margin(b = 4)),
        plot.background = element_rect(fill = "white", colour = NA))
save_fig(p_hemi, "postmortem_hemicycle.png", width = 10, height = 3.6)

# District level ----------------------------------------------------------------------------------------------------

bezirk_sim <- readRDS("output/sims_votes.rds")$bezirk_sim

actual_districts <- nr2024 %>%
  filter(str_detect(GKZ, "^G[0-9][A-Z]000$")) %>%
  pivot_longer(all_of(parties_2024), names_to = "party", values_to = "votes") %>%
  transmute(GKZ, party, actual_share = replace_na(votes, 0) / Stimmen_g,
            actual_turnout = Stimmen_g / Wahlberechtigte)
stopifnot(n_distinct(actual_districts$GKZ) == 39)

district_postmortem <- bezirk_sim %>%
  filter(party %in% main_parties) %>%
  inner_join(actual_districts, by = join_by(GKZ, party)) %>%
  group_by(GKZ, Gebietsname, state, party) %>%
  summarise(forecast_median = median(result),
            forecast_q05 = quantile(result, 0.05),
            forecast_q95 = quantile(result, 0.95),
            actual_share = first(actual_share),
            actual_percentile = mean(result < actual_share),
            turnout_median = median(pred_participation),
            actual_turnout = first(actual_turnout),
            .groups = "drop") %>%
  mutate(error = actual_share - forecast_median,
         inside_90 = actual_share >= forecast_q05 & actual_share <= forecast_q95)
stopifnot(nrow(district_postmortem) == 39 * length(main_parties))

write_csv(district_postmortem, "output/district_postmortem.csv")

district_coverage <- district_postmortem %>%
  group_by(party) %>%
  summarise(mean_abs_error = mean(abs(error)),
            mean_error = mean(error),
            share_inside_90 = mean(inside_90)) %>%
  left_join(party_order, by = "party") %>% arrange(order) %>% select(-order)
write_csv(district_coverage, "output/district_coverage.csv")

# Map: where each party beat / fell short of the forecast
error_map_parties <- c("FPÖ", "ÖVP", "SPÖ", "NEOS", "GRÜNE", "BIER")

p_district_error <- read_rwk_shapes() %>%
  inner_join(district_postmortem %>% filter(party %in% error_map_parties), by = "GKZ", relationship = "one-to-many") %>%
  mutate(party = factor(party, levels = error_map_parties)) %>%
  ggplot() +
  geom_sf(aes(fill = error), colour = "white", linewidth = 0.15) +
  facet_wrap(~ party, ncol = 3, labeller = as_labeller(party_labels)) +
  scale_fill_distiller(palette = "PuOr", direction = 1, limits = c(-0.08, 0.08), oob = scales::squish,
                       labels = scales::label_number(1, scale = 100, style_positive = "plus", suffix = " pts"),
                       name = "Result minus\nforecast") +
  labs(title = "Where the forecast missed",
       subtitle = "Actual vote share minus forecast median, by regional electoral district") +
  theme_map(base_size = 11) +
  theme(strip.text = element_text(face = "bold", size = 11),
        plot.subtitle = element_text(hjust = 0.5, margin = margin(b = 10)))
save_fig(p_district_error, "postmortem_district_error.png", width = 10, height = 4.6)
