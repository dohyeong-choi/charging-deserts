# Replication package for "Charging Deserts, Route Choice, and the Electrification of Interstate Trade"

Taejun Mo, Dohyeong Choi, Yilan Xu, and William Ridley (University of Illinois Urbana-Champaign)

> **Status (draft, 2026-11-08).** The folder structure and the final datasets on hand are in place. The analysis code, the table/figure code and the remaining final datasets are still to be added. Items marked **[TODO]** are open.

## Overview

The paper maps heavy-duty electric-truck charging stations onto the U.S. road network, computes charging-feasible routes between state population centers under four charging-network configurations, and embeds the resulting route- and technology-specific freight costs in a structural gravity model to simulate effects on trade and welfare.

**Scope of this package.** The package starts from the **final analysis datasets**:

- `data/`: final datasets, including bilateral route distances and freight costs by scenario, and trade flows (see [Dataset list](#dataset-list)).
- `code/01_analysis/`: gravity estimation and general-equilibrium counterfactuals. **[TODO]**
- `code/02_tables_figures/`: code that writes every table to `output/tables/` and every figure to `output/figures/`. **[TODO]**
- `output/`: tables and figures. Figures 1–3 are provided as static files (see below).

The geospatial analysis that produced the route distances is **not** part of the package. It covered station selection, road-network distances, and charging-feasible routing. The route distances it produced are provided as final data in `data/od_scenario_combined_all_atri2022.csv`. Its map outputs (Figures 1–3) are included as static files in `output/figures/`.

## Data Availability and Provenance Statements

### Statement about Rights

- [ ] I certify that the author(s) of the manuscript have legitimate access to and permission to use the data used in this manuscript.
- [ ] I certify that the author(s) of the manuscript have documented permission to redistribute/publish the data contained within this replication package. Appropriate permissions are documented in the LICENSE.txt file.

### License for Data

**[TODO: choose a license (e.g. CC-BY 4.0) and add LICENSE.txt.]**

### Summary of Availability

- [ ] All data **are** publicly available.
- [ ] Some data **cannot be made** publicly available.
- [ ] **No data can be made** publicly available.

**[TODO: tick once all final datasets are in.]**

### Final datasets

| File (in `data/`) | Content | Underlying sources | Provided |
|---|---|---|---|
| `od_scenario_combined_all_atri2022.csv` | Diesel and charging-feasible EV route distances, per-mile and total freight costs, connectivity/adoption indicators, by directed state pair and scenario | AFDC, NHS, Census COP (distances); ATRI, EIA (costs) | Yes |
| `trade_value_2012_2017_2022.csv` | Bilateral trade values, million 2022 USD | FAF5, FAF6 | Yes |
| **[TODO: gravity estimation sample, cost series, …]** | | | |

### Provenance of the route distances

The authors computed the bilateral route distances in `od_scenario_combined_all_atri2022.csv` with QGIS 3.44 (QNEAT3 plugin) and Python (NetworkX), from these public sources:

- **Alternative Fuels Data Center (AFDC), NREL / U.S. DOE.** Electric charging stations downloaded on 2025-11-30 from https://developer.nrel.gov/api/alt-fuel-stations/v1.json (83,578 stations). Heavy-duty stations (`maximum_vehicle_class = 'HD'`) within 1.1 miles of the contiguous-U.S. NHS: 106. Public domain.
- **National Highway System (NHS), USDOT BTS, National Transportation Atlas Database.** https://geodata.bts.gov/datasets/usdot::national-highway-system-nhs/about, downloaded November 2025. Public domain.
- **2020 state centers of population, U.S. Census Bureau.** https://www.census.gov/geographies/reference-files/time-series/geo/centers-population.html. Public domain.

The procedure is summarized in Section 3.2 of the paper:

- Each state's center of population is its node.
- Nodes are connected when their shortest NHS road distance is at most 400 miles.
- Dijkstra's algorithm finds the shortest charging-feasible path.
- Under the Existing Charging Network, only states with a heavy-duty station within 50 miles of their center of population can be an origin or destination.

### Provenance of the remaining data

**[TODO: for each source give the name, URL, version/vintage, access date, files used, and redistribution terms.]** These include at least:

- Freight Analysis Framework (FAF5 for 2012 and 2017; FAF6 for 2022), U.S. DOT BTS / FHWA.
- American Transportation Research Institute (ATRI), *An Analysis of the Operational Costs of Trucking* (various years).
- U.S. EIA, 2022 state commercial electricity prices.
- SimpleMaps U.S. Cities Database (Basic v1.93), if the intrastate distances are part of the final data. Its license does not allow redistributing the database itself; derived distances should be checked against the license.

## Dataset list

### `od_scenario_combined_all_atri2022.csv`

2,304 rows = 48 × 48 directed state pairs in the contiguous U.S. (same-state rows have missing distances).

| Column | Meaning |
|---|---|
| `origin_id`, `destination_id` | Origin / destination state name |
| `key_i`, `key_j` | Upper-case state names (merge keys) |
| `Total_i` | Diesel per-mile operating cost in the origin's ATRI region, 2022 ($/mi) |
| `Total_ev_i_dr` | Driver-operated electric truck per-mile cost ($/mi) |
| `Total_ev_i` | Autonomous electric truck per-mile cost ($/mi; excludes driver wages and benefits) |
| `dist` | Diesel Baseline road distance $D_{fuel}$ (miles, rounded to nearest 10) |
| `gas_cost` | `dist × Total_i` |
| `hd50_endpoint` | 1 if both states' centers of population have a heavy-duty charging station within 50 miles |
| `dist_400mi_realhd50`, `dist_400mi_cop`, `dist_400mi_cop_s3` | Charging-feasible EV route distance (miles, rounded to nearest 10; missing = no feasible route) under the Existing Charging Network ($D_{real}$), Population-Center Expansion ($D_{POP}$) and Strategic Network Expansion ($D_{STR}$) |
| `ev_cost_dr_400mi_*` / `ev_cost_400mi_*` | EV distance × driver / autonomous EV per-mile cost |
| `ev_choose_dr_400mi_*` / `ev_choose_400mi_*` | 1 if the EV total cost is below the diesel total cost |
| `indicator_dr_400mi_*` / `indicator_400mi_*` | 0 = no feasible route; 1 = feasible but diesel cheaper; 2 = electric adopted |

Scenario mapping: Existing Charging Network = `*_dr_400mi_realhd50`; Population-Center Expansion = `*_dr_400mi_cop`; Strategic Network Expansion = `*_dr_400mi_cop_s3`; Strategic Network + Autonomy = `*_400mi_cop_s3` (no `_dr`).

### `trade_value_2012_2017_2022.csv`

**[TODO: confirm definitions.]**

| Column | Meaning |
|---|---|
| `origin_id`, `destination_id` | Origin / destination state name |
| `intrastate` | 1 if origin = destination |
| `value_2012_mil2022usd`, `value_2017_mil2022usd`, `value_2022_mil2022usd` | Bilateral trade value, million 2022 USD |

**[TODO: variable lists for the remaining final datasets.]**

## Computational requirements

### Software Requirements

**[TODO: list the software (e.g. Stata/R/Python) and package versions used in `code/`, and provide a setup script.]**

### Controlled Randomness

**[TODO]**

- [ ] Random seed is set at line ___ of program ___
- [ ] No pseudo-random number generator is used.

### Memory, Runtime, Storage Requirements

**[TODO: runtime and machine description.]**

## Description of programs/code

- `code/01_analysis/`: gravity estimation (PPML with exporter-time and importer-time fixed effects) and general-equilibrium counterfactual simulations (θ = 4.14, with sensitivity runs at 2.79 and 4.46). **[TODO: file list and master script]**
- `code/02_tables_figures/`: writes the tables and figures listed below to `output/`. **[TODO: file list and master script]**

### License for Code

**[TODO: choose MIT/BSD/GPL and add LICENSE.txt.]**

## Instructions to Replicators

1. Install the software listed above. **[TODO]**
2. Run the master script in `code/01_analysis`. **[TODO: name]**
3. Run the master script in `code/02_tables_figures`. **[TODO: name]**
4. Tables and figures appear in `output/tables/` and `output/figures/`.

## List of tables and programs

The provided code reproduces:

- [ ] All numbers provided in text in the paper
- [ ] All tables and figures in the paper
- [x] Selected tables and figures in the paper, as explained below

| Figure/Table | Program | Output file | Note |
|---|---|---|---|
| Table 1 | **[TODO]** | `output/tables/sum_stat.tex` | Summary statistics |
| Table 2 | — | — | Scenario definitions; no data |
| Table 3 | **[TODO]** | `output/tables/estimation.tex` | Gravity estimates |
| Table 4 | **[TODO]** | `output/tables/network_comparison.tex` | Network development across scenarios |
| Figure 1 | not reproduced | `output/figures/basemap.pdf` | Static map from the geospatial analysis |
| Figure 2 | not reproduced | `output/figures/OD400_REAL.png`, `OD400_COP.png`, `OD400_COP_s3.png`, `OD400_legends.png` | Static maps from the geospatial analysis |
| Figure 3 | not reproduced | `output/figures/detour_real.pdf`, `detour_pop.pdf`, `detour_str.pdf`, `detour_str_auto.pdf` | Static maps from the geospatial analysis |
| Figure 4 | **[TODO]** | `output/figures/combined_connection_adoption.png` | |
| Figure 5 | **[TODO]** | `output/figures/new_feasible_trade_share_hosts_exporter_labeled.png` | |
| Figure 6 | **[TODO]** | `output/figures/combined_results_maps_welfare_inc_2x2.png` | |
| Figures A1–A3 | **[TODO]** | `output/figures/combined_results_maps_{perc,dollar,welfare_4x2}.png` | |
| Tables A1–A2 | **[TODO]** | `output/tables/atri_fuel_series.tex`, `energy_cost_regional.tex` | |
| Tables A3–A7 | **[TODO]** | `output/tables/{exports,imports,welfare}_perc.tex`, `{exports,imports}_value.tex` | |

## References

National Renewable Energy Laboratory (NREL). 2025. "Alternative Fuels Data Center Station Locator API (v1)." U.S. Department of Energy. https://developer.nrel.gov/docs/transportation/alt-fuel-stations-v1/ (accessed November 30, 2025).

U.S. Department of Transportation, Bureau of Transportation Statistics. 2025. "National Highway System (NHS)." National Transportation Atlas Database. https://geodata.bts.gov/datasets/usdot::national-highway-system-nhs/about (accessed November 2025).

U.S. Census Bureau. 2021. "Centers of Population Computation for the United States, 1950–2020." https://www2.census.gov/geo/pdfs/reference/cenpop2020/COP2020_documentation.pdf

**[TODO: FAF, ATRI, EIA and any other data references.]**

## Acknowledgements

This README follows the template of the Social Science Data Editors (https://social-science-data-editors.github.io/template_README/).
