# Replication package for "Charging Deserts, Route Choice, and the Electrification of Interstate Trade"

Taejun Mo, Dohyeong Choi, Yilan Xu, and William Ridley (University of Illinois Urbana-Champaign)

## Overview

The code reproduces Tables 1, 3, 4, and A1 to A7, Figures 4 to 6 and A1 to A3, and the numbers reported in the text. It starts from truck flows in the Freight Analysis Framework, diesel and charging-feasible route distances between states, and published per-mile operating costs. Figures 1 to 3 are maps drawn in QGIS and are included as files in `output/figures`. Table 2 defines the scenarios and uses no data.

## Software

- Stata 17 or later with `ftools`, `reghdfe`, `ppmlhdfe`, and `ge_gravity2`. `run_all.do` installs missing packages from SSC. The results were produced with StataNow 19 SE, ftools 2.37.0, reghdfe 5.7.3, ppmlhdfe 2.2.0, and ge_gravity2 3.0.
- Python 3 with the standard library only. Tested with Python 3.12.10.
- R with dplyr, ggplot2, cowplot, patchwork, scales, sf, usmap, usmapdata, maps, and ragg. Tested with R 4.3.2 (dplyr 1.1.4, ggplot2 3.5.2, cowplot 1.2.0, patchwork 1.3.2, scales 1.3.0, sf 1.0.20, usmap 0.7.0, usmapdata 0.2.1, maps 3.4.2, ragg 1.2.5).

The code draws no random numbers.

## Running the code

Set the working directory to this folder and run the three steps in order.

1. In Stata, `do run_all.do`
2. `python code/5_tables.py`
3. `Rscript code/6_figures.R`

Step 1 takes about ten seconds and step 3 about three minutes. Stata logs are written to `output/logs`.

| Script | Creates |
|---|---|
| `code/0_faf_extract.do` | `data/raw/faf/*.csv` from the original FAF files |
| `code/1_trade_flows.do` | `data/derived/trade_flows.csv` |
| `code/2_freight_costs.do` | `data/derived/freight_rates.csv`, `data/derived/freight_costs.csv` |
| `code/3_gravity.do` | `data/derived/gravity_sample.csv`, `gravity_estimates.csv`, `counterfactual_states.csv`, `counterfactual_pairs.csv` |
| `code/4_text_numbers.do` | `output/text_numbers.txt` |
| `code/5_tables.py` | `output/tables/*.tex` |
| `code/6_figures.R` | `output/figures/*.png` |

`run_all.do` runs scripts 1 to 4.

## Data

The inputs are in `data/raw`.

| File | Contents | Source |
|---|---|---|
| `faf/faf5_2012.csv` | 2012 shipment value, million 2017 dollars | FAF5.7.1 Reprocessed 1997-2012 State database |
| `faf/faf5_2017.csv` | 2017 shipment value, and 2022 value in 2017 and current dollars | FAF5.7.1 State database |
| `faf/faf6_2022.csv` | 2022 shipment value, million 2022 dollars | FAF6.0 State database |
| `route_distances.csv` | Diesel and charging-feasible electric route distances between states, in miles | Authors' routing on the National Highway System |
| `atri_regional_costs_2022.csv` | 2022 marginal operating cost per mile by cost item and ATRI region | ATRI, An Analysis of the Operational Costs of Trucking: 2023 Update, Table 13 |
| `atri_national_costs.csv` | National fuel cost and total marginal cost per mile, 2012-2024 | ATRI, annual Operational Costs of Trucking reports |
| `eia_electricity_prices_2022.csv` | 2022 average retail electricity price to the commercial sector by state, cents per kWh | EIA, Electric Power Annual 2022, Table 2.10 |
| `cpi_u.csv` | CPI-U annual averages, 2012-2024 | BLS |
| `states.csv` | State identifiers, FIPS codes, ATRI regions, the 11 western states, and the four states hosting the strategic stations | |
| `contiguity.csv` | Pairs of states that share a border | |

The three FAF files keep the original columns for truck shipments (`dms_mode` = 1) of domestic trade (`trade_type` = 1) between the 48 contiguous states. To recreate them, download `FAF5.7.1_State.zip` and `FAF5.7.1_Reprocessed_1997-2012_State.zip` from https://www.bts.gov/faf/faf5 and `FAF6.0_State.zip` from https://www.bts.gov/faf, place the unzipped CSV files in `data/raw/faf_original`, and run `do code/0_faf_extract.do` from this folder.

`route_distances.csv` gives the diesel route distance (`dist_fuel`) and the charging-feasible electric route distance under the Existing Charging Network (`dist_real`), the Population-Center Expansion (`dist_pop`), and the Strategic Network Expansion (`dist_str`). Interstate distances are rounded to the nearest 10 miles. For pairs with the same origin and destination, `dist_fuel` is the intrastate distance. Electric route distances are blank for intrastate pairs and for pairs without a charging-feasible route.

The route distances were computed with QGIS 3.44 (QNEAT3 plugin) and Python (NetworkX) by the procedure in Section 3.2 of the paper, using four sources.

- Electric charging stations from the Alternative Fuels Data Center (National Renewable Energy Laboratory and U.S. Department of Energy), downloaded on November 30, 2025 from https://developer.nrel.gov/api/alt-fuel-stations/v1.json.
- The National Highway System from the National Transportation Atlas Database (Bureau of Transportation Statistics), downloaded in November 2025 from https://geodata.bts.gov/datasets/usdot::national-highway-system-nhs/about.
- The 2020 state centers of population from the U.S. Census Bureau, https://www.census.gov/geographies/reference-files/time-series/geo/centers-population.html.
- The United States Cities Database, Basic Version 1.93, from SimpleMaps, https://simplemaps.com/data/us-cities. The intrastate distance is based on the two most populous cities in each state. The database is not included.

## Tables, figures, and numbers in the text

| Paper | File in `output` |
|---|---|
| Table 1 | `tables/sum_stat.tex` |
| Table 3 | `tables/estimation.tex` |
| Table 4 | `tables/network_comparison.tex` |
| Table A1 | `tables/atri_fuel_series.tex` |
| Table A2 | `tables/energy_cost_regional.tex` |
| Tables A3 to A7 | `tables/exports_perc.tex`, `tables/imports_perc.tex`, `tables/welfare_perc.tex`, `tables/exports_value.tex`, `tables/imports_value.tex` |
| Figure 1 | `figures/basemap.pdf` |
| Figure 2 | `figures/OD400_REAL.pdf`, `figures/OD400_COP.pdf`, `figures/OD400_COP_s3.pdf`, `figures/OD400_Legends.pdf` |
| Figure 3 | `figures/detour_real.pdf`, `figures/detour_pop.pdf`, `figures/detour_str.pdf`, `figures/detour_str_auto.pdf` |
| Figure 4 | `figures/combined_connection_adoption.png` |
| Figure 5 | `figures/new_feasible_trade_share_hosts_exporter_labeled.png` |
| Figure 6 | `figures/combined_results_maps_welfare_inc_2x2.png` |
| Figure A1 | `figures/combined_results_maps_perc.png` |
| Figure A2 | `figures/combined_results_maps_dollar.png` |
| Figure A3 | `figures/combined_results_maps_welfare_4x2.png` |
| Numbers in the text | `text_numbers.txt`, listed by section |

## Derived data

States are identified by upper-case names with underscores, as in `states.csv`. Trade values are in millions of 2022 dollars.

- `trade_flows.csv`: `year`, `origin`, `destination`, and `trade`, truck-served domestic shipments for 2012, 2017, and 2022.
- `freight_rates.csv`: per-mile costs by ATRI region. `electricity_price` is in cents per kWh, `energy_ev` is the electricity cost per mile at 2 kWh per mile, and `fuel`, `wages`, and `benefits` are ATRI cost items. `rate_fuel`, `rate_ev_dr`, and `rate_ev_ndr` are the per-mile costs of diesel, driver-operated electric, and autonomous electric trucks.
- `freight_costs.csv`: for each state pair, route distances (`dist_*`, miles), trip costs (`cost_*`, dollars), and route status by scenario (`status_*`: 0 = no charging-feasible route, 1 = feasible but diesel is cheaper, 2 = electric trucking adopted).
- `gravity_sample.csv`: the estimation sample, with `trade`, the diesel trip cost `cost_fuel`, and the indicators `contiguous` and `intrastate`.
- `gravity_estimates.csv`: PPML coefficients and standard errors, number of observations, pseudo R-squared, and number of clusters.
- `counterfactual_states.csv`: for each `theta`, `scenario`, and `state`, the percent changes in real exports, real imports, and welfare relative to the Diesel Baseline (`exports_pct`, `imports_pct`, `welfare_pct`), the changes in real exports and imports in millions of 2022 dollars (`exports_diff`, `imports_diff`), and the equivalent variation in millions of 2022 dollars (`welfare_diff`), equal to `welfare_pct` / 100 times the state's 2022 expenditure on truck-served shipments from all states including itself.
- `counterfactual_pairs.csv`: for each `theta`, `scenario`, and state pair, baseline trade (`trade`) and counterfactual nominal trade (`trade_cf`).

Scenario codes are `real` (Existing Charging Network), `pop` (Population-Center Expansion), `str` (Strategic Network Expansion), and `auto` (Strategic Network + Autonomy). The trade elasticity `theta` is 4.14 in the main results and 2.79 and 4.46 in the L and H columns of the appendix tables.
