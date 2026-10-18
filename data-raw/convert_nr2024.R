
# Converts the official final result of the 2024 National Council election (BMI, Bundeswahlbehörde decision of
# 16 Oct 2024) into the same semicolon CSV layout as the other files in data/election_results/.
# Source: https://www.bmi.gv.at/412/Nationalratswahlen/Nationalratswahl_2024/
#
# NR2024 is deliberately NOT part of get_election_results(): it is only used to score the forecast (05_postmortem.R).

library(tidyverse)
library(readxl)

raw <- read_excel("data/election_results/originals/NR2024.xlsx", col_names = FALSE, .name_repair = "minimal")

header <- unlist(raw[1, ])
keep <- header != "%"                       # drop the percentage columns, keep counts

nr2024 <- raw[-1, keep] %>%
  set_names(header[keep]) %>%
  rename(Stimmen_abg = Abgegebene, Stimmen_ung = Ungültige, Stimmen_g = Gültige) %>%
  mutate(across(-c(GKZ, Gebietsname), as.numeric))

# sanity checks against the published federal totals
national <- nr2024 %>% filter(GKZ == "G00000")
stopifnot(national$Stimmen_g == 4882888,
          national$Stimmen_g == sum(select(national, ÖVP:KEINE)),
          nrow(nr2024 %>% filter(str_detect(GKZ, "^G[0-9][A-Z]000$"))) == 39)

write_csv2(nr2024, "data/election_results/NR2024.csv", na = "")
