
# Constants ---------------------------------------------------------------------------------------------------------

# Date the final forecast was run. Poll recency weights are computed relative to this date, so pinning it is what
# makes the forecast reproducible (the original code used Sys.Date()).
FORECAST_DATE <- as.Date("2024-09-27")

parties_2024 <- c("ÖVP", "SPÖ", "FPÖ", "GRÜNE", "NEOS", "KPÖ", "BIER", "LMP", "KEINE")

party_order <- tibble(party = parties_2024,
                      order = seq_along(parties_2024))

party_labels <- c("ÖVP" = "ÖVP", "SPÖ" = "SPÖ", "FPÖ" = "FPÖ", "GRÜNE" = "Grüne", "NEOS" = "NEOS",
                  "KPÖ" = "KPÖ", "BIER" = "Bierpartei", "LMP" = "LMP", "KEINE" = "KEINE")

color_palette <- c("FPÖ"   = "#0056a2",
                   "SPÖ"   = "#e3000f",
                   "ÖVP"   = "#63c3d0",
                   "GRÜNE" = "#51a51e",
                   "NEOS"  = "#e84188",
                   "KPÖ"   = "#aa0000",
                   "BIER"  = "#ffcc00",
                   "LMP"   = "grey",
                   "KEINE" = "black")

# Import Functions --------------------------------------------------------------------------------------------------

# Reads the BMI result files (one per election) and tags each row with its level:
# Bund (federal) > Bundesland (state) > Wahlbezirk (regional electoral district) > Gemeinde (municipality)
get_election_results <- function(dir = "data/election_results"){
  # NB: order matters - downstream code selects party columns by position range (ÖVP:BIER)
  elections <- tibble(type = c("EU", "EU", "EU", "NR", "NR", "NR", "NR", "NR", "NR"),
                      year = c(2014, 2019, 2024, 2013, 2017, 2019, 2002, 2006, 2008)) %>%
    mutate(code = file.path(dir, paste0(type, year, ".csv")))

  total_results <- tibble()
  for(i in seq_len(nrow(elections))){
    temp_results <- read_csv2(elections$code[i], show_col_types = F, progress = F) %>%
      mutate(type = elections$type[i],
             year = elections$year[i])

    total_results <- bind_rows(total_results, temp_results) %>%
      select(type, year, everything())
  }

  total_results <- total_results %>%
    mutate(category = case_when(GKZ == "G00000" ~ "Bund",
                                grepl("0000", GKZ) ~ "Bundesland",
                                grepl("000", GKZ) & grepl("[A-Za-z]", str_sub(GKZ, 2, 9)) ~ "Wahlbezirk",
                                T ~ "Gemeinde"))

  total_results %>%
    mutate(state_gkz = paste0(str_sub(GKZ, 1, 2), "0000")) %>%
    left_join(total_results %>%
                filter(category == "Bundesland") %>%
                select(state_gkz = GKZ, state = Gebietsname) %>%
                distinct() %>%
                drop_na(state), by = "state_gkz") %>%
    select(-state_gkz) %>%
    mutate(participation = Stimmen_g / Wahlberechtigte) %>%
    select(type, year, category, participation, everything()) %>%
    mutate(Gebietsname = str_replace(Gebietsname, "Briefwahl", "Wahlkarten")) %>%
    mutate(Gebietsname = ifelse(GKZ == "G3G000", "Niederösterreich Ost", Gebietsname))
}

# Polls from the @Wahlen_AT collection, weighted by survey method and recency (relative to `as_of`)
get_polling_data <- function(path = "data/polling/polls.csv", as_of = FORECAST_DATE, confidence = 0.7){
  polls <- read_csv2(path, show_col_types = F) %>%
    mutate(date = as.Date(date, format = "%d.%m.%Y"))

  polls %>%
    mutate(respondents_clean = as.numeric(respondents_clean)) %>%
    mutate(rating = case_when(method == "Result" ~ 1,
                              method == "Persönlich+Online" ~ 0.7,
                              method == "Telefonisch+Online" ~ 0.6,
                              method == "Online" ~ 0.5,
                              is.na(method) ~ 0.05,
                              T ~ 0.1)) %>%
    mutate(recency = recency_weight(as.numeric(as_of - date), lambda = 0.02)) %>%
    mutate(total_weight = rating * recency) %>%
    drop_na(respondents_clean) %>%
    mutate(across(c(ÖVP:Sonstige), ~ margin_of_error(.x, respondents_clean, confidence_level = confidence),
                  .names = "{col}_moe"))
}

# Helper Functions --------------------------------------------------------------------------------------------------

recency_weight <- function(days_since_poll, lambda = 0.05) {
  exp(-lambda * days_since_poll)
}

margin_of_error <- function(party_percent, sample_size, confidence_level = 0.95) {
  z_score <- qnorm((1 + confidence_level) / 2)
  z_score * sqrt((party_percent * (1 - party_percent)) / sample_size)
}

# Votes as share of valid votes, by party and area, joined to the national share of the same election.
# reg_swing = how much better/worse a party does in an area than nationally.
# fill_national_na: if FALSE, elections a party didn't contest nationally are dropped (used for the swing estimates);
# if TRUE they are kept with a national share of 0 (used for the correlation matrices).
calc_regional_swing_long <- function(election_results, categories, fill_national_na = FALSE){
  national <- election_results %>% filter(category == "Bund")
  if(fill_national_na) national <- national %>% mutate(across(c(ÖVP:BIER), ~ replace_na(.x, 0)))

  election_results %>%
    mutate(across(c(ÖVP:BIER), ~ replace_na(.x, 0))) %>%
    filter(category %in% categories) %>%
    pivot_longer(cols = c(ÖVP:BIER), names_to = "party", values_to = "votes") %>%
    mutate(pct = votes / Stimmen_g) %>%
    left_join(national %>%
                pivot_longer(cols = c(ÖVP:BIER), names_to = "party", values_to = "votes") %>%
                mutate(nat_pct = votes / Stimmen_g) %>%
                select(year, type, party, nat_pct),
              by = join_by(type, year, party)) %>%
    drop_na(nat_pct) %>%
    mutate(reg_swing = pct - nat_pct)
}

# Pads a 6x6 party correlation matrix with uncorrelated rows/cols for the parties with no electoral history
pad_minor_parties <- function(m){
  m <- rbind(m,
             "BIER"  = c(0, 0, 0, 0, 0, 0),
             "LMP"   = c(0, 0, 0, 0, 0, 0),
             "KEINE" = c(0, 0, 0, 0, 0, 0))
  cbind(m,
        "BIER"  = c(0, 0, 0, 0, 0, 0, 1, 0, 0),
        "LMP"   = c(0, 0, 0, 0, 0, 0, 0, 1, 0),
        "KEINE" = c(0, 0, 0, 0, 0, 0, 0, 0, 1))
}
