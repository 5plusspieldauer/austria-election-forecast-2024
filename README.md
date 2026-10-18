# Forecasting the 2024 Austrian election

A simulation model for the **29 September 2024 Austrian National Council election**, built in R from public polls and
past election results.

The model simulates the election 10,000 times down to each of the 39 regional electoral districts. It combines three
components:

- a correlated national trend from a weighted polling average
- correlated regional swings from past results
- correlated district turnout

Every simulation then goes through Austria's three-tier seat-allocation law to produce a full 183-seat parliament.

<p align="center"><img src="figures/national_vote_simulation.png" alt="Simulated national vote share"></p>

- **[MODEL.md](MODEL.md)** explains how the model works, step by step.
- **[POSTMORTEM.md](POSTMORTEM.md)** compares the final forecast (27 September 2024) with the official result.

## Reproducing it

Requires R ≥ 4.3 and the packages `tidyverse`, `MASS`, `sf`, `ragg`, `patchwork` and `scales` (plus `readxl` for
`data-raw/`).

```bash
Rscript run_forecast.R
```

This takes about a minute. It reproduces the 27 September forecast exactly: same seed, same model inputs, and poll
weights computed as of the forecast date. It also redraws every figure and writes summary tables to `output/`.

| Path | What |
|:---|:---|
| `R/` | Model functions (data import, simulation, D'Hondt) and plot helpers |
| `scripts/01_model_inputs.R` | Estimates regional swings, correlations and turnout from past elections (optional, see below) |
| `scripts/02_simulate.R` | National → turnout → district simulation, aggregated to states and nation |
| `scripts/03_allocate_seats.R` | Three-tier seat allocation, coalition odds |
| `scripts/04_figures.R` | Figures for MODEL.md |
| `scripts/05_postmortem.R` | Forecast vs. official result |
| `model/` | Model inputs exactly as used on 27 September |
| `output/*.csv` | Forecast summary, seat distribution, coalition odds, post-mortem tables |
| `data/` | Election results 2002–2024 (BMI), polls, seat quotas, district shapefile |
| `data-raw/` | Conversion of the official 2024 result file |

`model/` ships the inputs as they were on forecast day. Re-running `01_model_inputs.R` (set `REESTIMATE_INPUTS <- TRUE`
in `run_forecast.R`) gives slightly different correlations, because the 2002–2008 results were added to `data/` after
those inputs were estimated.

## Data sources

- **Election results:** Austrian Federal Ministry of the Interior ([bmi.gv.at](https://www.bmi.gv.at/412/)). The 2024
  National Council result is the final result as certified by the Federal Electoral Board on 16 October 2024. It is
  used only for the post-mortem, never as a model input.
- **Polls:** the [@Wahlen_AT](https://twitter.com/Wahlen_AT) poll collection.
- **District boundaries:** Statistik Austria, Regionalwahlkreise 2024.
