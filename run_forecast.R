
# Reproduces the final pre-election forecast (as of 2024-09-27) end to end.
# Run from the repo root:  Rscript run_forecast.R
# Takes a few minutes; the full simulation output (~150 MB) lands in output/*.rds and is not committed.

suppressPackageStartupMessages({
  library(tidyverse)
})
options(scipen = 9999)

source("R/functions.R")
source("R/sim_functions.R")

n_sims <- 10^4

# model/ ships the inputs exactly as used for the 2024-09-27 forecast. They were estimated before the 2002-2008
# results were added to data/, so re-estimating them now gives slightly different correlations and a different
# forecast. Set to TRUE to re-estimate (overwrites model/).
REESTIMATE_INPUTS <- FALSE

if(REESTIMATE_INPUTS){
  message("1/5 Estimating model inputs"); source("scripts/01_model_inputs.R")
} else {
  message("1/5 Using model inputs as run on ", FORECAST_DATE)
}
message("2/5 Simulating votes");         source("scripts/02_simulate.R")
message("3/5 Allocating seats");         source("scripts/03_allocate_seats.R")
message("4/5 Drawing figures");          source("scripts/04_figures.R")
message("5/5 Post-mortem");              source("scripts/05_postmortem.R")
