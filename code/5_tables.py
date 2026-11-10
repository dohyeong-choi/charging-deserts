import csv
import math
import statistics
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

RAW = Path("data/raw")
DERIVED = Path("data/derived")
TABLES = Path("output/tables")
SCENARIOS = ["real", "pop", "str", "auto"]
THETAS = ["4.14", "2.79", "4.46"]
SCENARIO_NAMES = {
    "real": "Existing Charging Network",
    "pop": "Population-Center Expansion",
    "str": "Strategic Network Expansion",
    "auto": "Strategic Network + Autonomy",
}
MINUS = r"$\llap{$-$}$"


def read(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def half_up(x, digits):
    return Decimal(repr(float(x))).quantize(Decimal(1).scaleb(-digits), rounding=ROUND_HALF_UP)


def fixed(x, digits):
    return str(half_up(x, digits))


def integer(x):
    return f"{int(half_up(x, 0)):,d}"


def significant(x, digits):
    if x == 0:
        return fixed(0, digits)
    return fixed(float(half_up(x, 2 - math.floor(math.log10(abs(x))))), digits)


def signed(text):
    return MINUS + text[1:] if text.startswith("-") else text


def write(name, text):
    (TABLES / f"{name}.tex").write_text(text, encoding="utf-8", newline="\n")


states = {r["state"]: r for r in read(RAW / "states.csv")}
costs = read(DERIVED / "freight_costs.csv")
distance = {(r["origin"], r["destination"]): float(r["dist_fuel"]) for r in costs}
trade_2022 = {(r["origin"], r["destination"]): float(r["trade"]) for r in read(DERIVED / "trade_flows.csv") if r["year"] == "2022"}


sample = read(DERIVED / "gravity_sample.csv")
groups = [("All        ", lambda r: True), ("Intrastate   ", lambda r: r["intrastate"] == "1"), ("Interstate", lambda r: r["intrastate"] == "0")]


def summary_rows(values_of):
    out = []
    for label, keep in groups:
        v = [values_of(r) for r in sample if keep(r)]
        out.append(rf"\quad {label} & {len(v):,d} & {statistics.fmean(v):,.2f} & {statistics.stdev(v):,.2f} & {max(v):,.2f} \\")
    return "\n".join(out)


write("sum_stat", r"""\begin{table}[ht]
\centering
\caption{Summary Statistics}
\label{tab:summary_stats}
\begin{threeparttable}
\begin{tabular}{l>{\hspace{1.5em}}r>{\hspace{1.5em}}r>{\hspace{1.5em}}r>{\hspace{1.5em}}r}
\hline\hline
 & Obs. & Mean & Std. Dev. & Max \\
\hline
\multicolumn{5}{l}{\textit{Trade value (million USD)}} \\
""" + summary_rows(lambda r: float(r["trade"])) + r"""
\hline
\multicolumn{5}{l}{\textit{Distance (miles)}} \\
""" + summary_rows(lambda r: distance[(r["origin"], r["destination"])]) + r"""
\hline\hline
\end{tabular}

\begin{tablenotes}[online,flushleft]
    \small
    \item \textit{Notes:} Data on bilateral trade values for the lower 48 U.S. states are for the years 2012, 2017, and 2022, and are taken from the FAF5 (2012 and 2017) and FAF6 (2022) datasets from the Bureau of Transportation Statistics. Data on bilateral distances are calculated according to the procedure described in the text. Distances refer to least-cost diesel routes; electric route distances, defined only for charging-feasible pairs, are summarized in Table~\ref{tab:network_development}.
 \end{tablenotes}""" + "\n \n" + r"""\end{threeparttable}
 \end{table}""")


estimates = {r["term"]: r for r in read(DERIVED / "gravity_estimates.csv")}
coef = {k: signed(fixed(float(v["coef"]), 3)) for k, v in estimates.items()}
se = {k: fixed(float(v["se"]), 3) for k, v in estimates.items()}
nobs = f"{int(estimates['ln_cost']['nobs']):,d}"
pseudo_r2 = fixed(float(estimates["ln_cost"]["pseudo_r2"]), 3)
write("estimation", r"""\begin{table}[H]
\centering
\caption{Gravity Estimation Results}
\label{tab:gravity_aggregate}
\begin{threeparttable}
\begin{tabular}{l>{\hspace{3em}}c}
\hline\hline
Variable & \\
\hline
$\log(t_{ijt})$ & """ + coef["ln_cost"] + r""" \\
                 & (""" + se["ln_cost"] + r""") \\
$C_{ij}$        & """ + coef["contiguous"] + r""" \\
                 & (""" + se["contiguous"] + r""") \\
$H_{ij}$         & """ + coef["intrastate"] + r""" \\
                 & (""" + se["intrastate"] + r""") \\
 & \\
Exporter $\times$ Time FE    & $\checkmark$ \\
Importer $\times$ Time FE    & $\checkmark$ \\
Observations                 & """ + nobs + r""" \\
Pseudo $R^2$                 & """ + pseudo_r2 + r""" \\
\hline\hline""" + "\n \n" + r"""\end{tabular}

\begin{tablenotes}[online,flushleft]
    \small
    \item \textit{Notes:} Estimation of equation \eqref{eq:gravity_est} by PPML. $t_{ijt}$ is the trucking cost of shipping from $i$ to $j$, equal to the least-cost diesel route distance multiplied by the ATRI marginal operating cost per mile in the origin state's region; $C_{ij}$ is an indicator variable for contiguous borders, and $H_{ij}$ is an indicator for intrastate trade (observations for which $i=j$). Standard errors clustered at the bilateral pair level. All estimates are significant at the $p<0.01$ level.
 \end{tablenotes}""" + "\n \n" + r"""\end{threeparttable}
\end{table}""")


pairs = [r for r in costs if r["origin"] != r["destination"]]
for r in pairs:
    r["trade"] = trade_2022[(r["origin"], r["destination"])]
    r["cross"] = states[r["origin"]]["west"] != states[r["destination"]]["west"]
total_trade = sum(r["trade"] for r in pairs)
n_cross = sum(r["cross"] for r in pairs)
panel_a, panel_b, panel_c = [], [], []
for s in SCENARIOS:
    name = f"{SCENARIO_NAMES[s]:<29s}"
    route = "str" if s == "auto" else s
    feasible = [r for r in pairs if int(r[f"status_{s}"]) > 0]
    adopting = [r for r in pairs if int(r[f"status_{s}"]) == 2]
    feasible_share = fixed(100 * sum(r["trade"] for r in feasible) / total_trade, 1)
    adopting_share = fixed(100 * sum(r["trade"] for r in adopting) / total_trade, 1)
    panel_a.append(rf"{name}& {len(feasible):<5,d} & {feasible_share} & {sum(r['cross'] for r in feasible):<3d} & {len(adopting):<5,d} & {adopting_share} \\")
    for status, panel in ((2, panel_b), (1, panel_c)):
        group = [r for r in pairs if int(r[f"status_{s}"]) == status]
        electric = [float(r[f"dist_{route}"]) for r in group]
        diesel = [float(r["dist_fuel"]) for r in group]
        saving = [float(r["cost_fuel"]) - float(r[f"cost_{s}"]) for r in group]
        saving_pct = [100 * x / float(r["cost_fuel"]) for x, r in zip(saving, group)]
        detour = statistics.fmean(e / d for e, d in zip(electric, diesel))
        panel.append(
            rf"{name}& {len(group):<5,d} & {integer(statistics.fmean(electric)):<5s} & {integer(statistics.stdev(electric)):<5s} & "
            rf"{integer(max(electric))} & {integer(statistics.fmean(diesel)):<5s} & {fixed(detour, 2)} & "
            rf"{signed(integer(statistics.fmean(saving))):<5s} & {signed(fixed(statistics.fmean(saving_pct), 1))} \\"
        )

write("network_comparison", r"""\begin{table}[!htbp]
\centering
\caption{Network Development, Route Distances, and Variable Cost Savings Across Charging Scenarios}
\label{tab:network_development}
\footnotesize
\setlength{\tabcolsep}{2pt}

\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}lccccc@{}}
\hline
\hline
& \multicolumn{3}{c}{Connectivity} & \multicolumn{2}{c}{Adoption} \\
\cmidrule(lr){2-4}\cmidrule(lr){5-6}
Scenario
& \begin{tabular}[b]{@{}c@{}}Feasible\\pairs\end{tabular}
& \begin{tabular}[b]{@{}c@{}}Trade\\share (\%)\end{tabular}
& \begin{tabular}[b]{@{}c@{}}East--West\\pairs\end{tabular}
& \begin{tabular}[b]{@{}c@{}}Adopting\\pairs\end{tabular}
& \begin{tabular}[b]{@{}c@{}}Trade\\share (\%)\end{tabular} \\
\hline
\multicolumn{6}{@{}l}{\textit{Panel A: Connectivity and adoption}} \\
""" + "\n".join(panel_a) + r"""
\hline
\end{tabular*}

\vspace{8pt}

\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}lcccccccc@{}}
\hline
& & \multicolumn{4}{c}{Route distance (miles)} & & \multicolumn{2}{c}{\begin{tabular}[b]{@{}c@{}}Variable cost\\saving per trip\end{tabular}} \\
\cmidrule(lr){3-6}\cmidrule(lr){8-9}
Scenario
& Pairs
& \begin{tabular}[b]{@{}c@{}}Electric\\mean\end{tabular}
& \begin{tabular}[b]{@{}c@{}}Electric\\std.\ dev.\end{tabular}
& \begin{tabular}[b]{@{}c@{}}Electric\\max\end{tabular}
& \begin{tabular}[b]{@{}c@{}}Diesel\\mean\end{tabular}
& \begin{tabular}[b]{@{}c@{}}Detour\\ratio\end{tabular}
& (\$) & (\%) \\
\hline
\multicolumn{9}{@{}l}{\textit{Panel B: Adopting pairs}} \\
""" + "\n".join(panel_b) + r"""
\hline
\multicolumn{9}{@{}l}{\textit{Panel C: Feasible pairs remaining on diesel}} \\
""" + "\n".join(panel_c) + r"""
\hline
\hline
\end{tabular*}

\vspace{0.5em}
\begin{minipage}{\textwidth}
\footnotesize
\textit{Notes:} There are """ + f"{len(pairs):,d}" + r""" interstate state pairs. A pair is \emph{feasible} when an electrically feasible route exists under the charging network of the scenario, irrespective of relative operating cost, and \emph{adopting} when electric or autonomous electric trucking is also cheaper than diesel. In Panel A, trade shares report the percentage of baseline interstate truck-served trade on links in the corresponding category, and East--West pairs are the feasible pairs among the """ + f"{n_cross:,d}" + r""" pairs linking a western state to a state east of the Rockies. Panels B and C summarize adopting pairs and feasible pairs that continue to ship by diesel. Electric route distance is the shortest charging-feasible route and diesel distance the least-cost road route between the population centers of the two states; the detour ratio is the electric distance divided by the diesel distance of the pair. The variable cost of a trip is the route distance multiplied by the ATRI marginal operating cost per mile, which reflects 2022 operating costs, of the technology in the origin state's region (Subsection~\ref{subsec:cfl_scenarios}), and the saving is the diesel cost less the electric or autonomous electric cost. Detour ratios and savings are averaged over pairs. In Panel C the savings are negative: the charging-feasible route would raise the variable cost of the trip, and these pairs remain on diesel. The Strategic Network Expansion and Strategic Network + Autonomy share the same charging network and hence have identical connectivity.
\end{minipage}
\end{table}""")


cpi = {r["year"]: float(r["cpi_u"]) for r in read(RAW / "cpi_u.csv")}
fuel_rows = []
for r in read(RAW / "atri_national_costs.csv"):
    fuel, total = float(r["fuel"]), float(r["total"])
    fuel_rows.append(rf"{r['year']} & {fixed(fuel, 3)} & {fixed(total, 3)} & {fixed(100 * fuel / total, 1)} & {fixed(fuel * cpi['2022'] / cpi[r['year']], 3)} \\")
write("atri_fuel_series", r"""\begin{table}[htbp]
\centering
\caption{Fuel Cost per Mile in U.S. Trucking, 2012--2024}
\label{tab:atri_fuel_series}
\begin{threeparttable}
\begin{tabular}{l>{\hspace{1.5em}}r>{\hspace{1.5em}}r>{\hspace{1.5em}}r>{\hspace{1.5em}}r}
\hline\hline
Year & Fuel cost & Total marginal cost & Fuel share & Fuel cost \\
     & (\$/mile)  & (\$/mile)           & (\%)        & (2022 \$/mile) \\
\hline
""" + "\n".join(fuel_rows) + r"""
\hline\hline
\end{tabular}
\begin{tablenotes}[online,flushleft]
    \small
    \item \textit{Notes:} Fuel cost and total marginal cost per mile are from the ``Average Marginal Costs per Mile'' table of ATRI's annual Operational Costs of Trucking reports. The final column deflates the nominal fuel cost to constant 2022 dollars. The 2022 fuel cost of \$0.641 per mile is identical in nominal terms to its 2012 level and lower in real terms than in 2012, 2013, and 2014.
 \end{tablenotes}
\end{threeparttable}
\end{table}
""")


energy_rows = []
for r in read(DERIVED / "freight_rates.csv"):
    price, energy, fuel = float(r["electricity_price"]), float(r["energy_ev"]), float(r["fuel"])
    energy_rows.append(rf"{r['atri_region']:<9s} & {price:.2f} & {energy:.3f} & {fuel:.3f} & {energy / fuel:.3f} \\")
write("energy_cost_regional", r"""\begin{table}[htbp]
\centering
\caption{Regional Energy Costs of Diesel and Electric Trucking, 2022}
\label{tab:energy_cost_regional}
\begin{threeparttable}
\begin{tabular}{l>{\hspace{1.5em}}r>{\hspace{1.5em}}r>{\hspace{1.5em}}r>{\hspace{1.5em}}r}
\hline\hline
Region & Electricity price & Electric energy cost & Diesel fuel cost & Cost ratio \\
       & (cents/kWh)       & (\$/mile)            & (\$/mile)        & (electric/diesel) \\
\hline
""" + "\n".join(energy_rows) + r"""
\hline\hline
\end{tabular}
\begin{tablenotes}[online,flushleft]
    \small
    \item \textit{Notes:} Electricity prices are 2022 average retail prices to the commercial sector by state (EIA, Electric Power Annual, Table 2.10), averaged over the states in each ATRI region. The electric energy cost per mile applies the consumption rate of 2 kWh per mile. The diesel fuel cost per mile is the region-specific 2022 marginal fuel cost from ATRI. The final column is the ratio of electric to diesel energy cost per mile, which determines the region-specific reduction applied to the fuel component of the diesel baseline in the electric truck scenarios.
 \end{tablenotes}
\end{threeparttable}
\end{table}
""")


results = {(r["theta"], r["scenario"], r["state"]): r for r in read(DERIVED / "counterfactual_states.csv")}
theta_key = {t: next(k for k in {key[0] for key in results} if float(k) == float(t)) for t in THETAS}
COMMON = (r"Column groups (1)--(4) are the Existing Charging Network, the Population-Center Expansion, the Strategic Network Expansion, "
          r"and Strategic Network + Autonomy, as defined in Table~\ref{tab:counterfactual_scenarios}. L and H denote the simulation results "
          r"utilizing the lower and upper bounds of the trade elasticity $\theta$ derived from the estimates in \cite{simonovska2014elasticity} "
          r"($\theta = 2.79$ and $\theta = 4.46$); columns labeled Base use the benchmark value $\theta = 4.14$.")
APPENDIX = [
    ("exports_perc", "exports_pct", lambda x: significant(x, 2), r"State-Level Export Changes (\%)", "tab:appendix_export_changes", "%",
     r"Percentage changes in state-level exports relative to the Diesel Baseline of Table~\ref{tab:counterfactual_scenarios}. " + COMMON),
    ("imports_perc", "imports_pct", lambda x: significant(x, 2), r"State-Level Import Changes (\%)", "tab:appendix_import_changes", "%",
     r"Percentage changes in state-level imports relative to the Diesel Baseline of Table~\ref{tab:counterfactual_scenarios}. " + COMMON),
    ("welfare_perc", "welfare_pct", lambda x: significant(x, 3), r"State-Level Welfare Changes (\%)", "tab:appendix_welfare_changes", "",
     r"Percentage changes in state-level welfare relative to the Diesel Baseline of Table~\ref{tab:counterfactual_scenarios}. " + COMMON
     + r" Welfare responses scale approximately in proportion to $1/\theta$, so the L columns are larger in absolute value than the H columns throughout: gains are larger and losses deeper at $\theta = 2.79$."),
    ("exports_value", "exports_diff", integer, r"State-Level Export Changes (million USD)", "tab:appendix_export_changes_dollar", "%",
     r"Changes in the value of state-level exports relative to the Diesel Baseline of Table~\ref{tab:counterfactual_scenarios}, in millions of constant 2022 dollars. " + COMMON
     + r" This table is the level counterpart of Table~\ref{tab:appendix_export_changes}."),
    ("imports_value", "imports_diff", integer, r"State-Level Import Changes (million USD)", "tab:appendix_import_changes_dollar", "%",
     r"Changes in the value of state-level imports relative to the Diesel Baseline of Table~\ref{tab:counterfactual_scenarios}, in millions of constant 2022 dollars. " + COMMON
     + r" This table is the level counterpart of Table~\ref{tab:appendix_import_changes}."),
]
for name, variable, formatter, caption, label, end_mark, note in APPENDIX:
    body = []
    for state in sorted(states):
        cells = [signed(formatter(float(results[(theta_key[t], s, state)][variable]))) for s in SCENARIOS for t in THETAS]
        body.append(states[state]["name"] + " & " + " & ".join(cells) + r" \\")
    write(name, r"""\begin{table}[htbp]
\centering
\caption{""" + caption + r"""}
\label{""" + label + r"""}
\begin{threeparttable}
\renewcommand{\arraystretch}{0.8}
\footnotesize
\begin{tabularx}{\textwidth}{lYYYYYYYYYYYY}
\hline\hline
State & \multicolumn{3}{c}{(1)} & \multicolumn{3}{c}{(2)} & \multicolumn{3}{c}{(3)} & \multicolumn{3}{c}{(4)} \\
\cline{2-4}\cline{5-7}\cline{8-10}\cline{11-13}
 & Base & L & H & Base & L & H & Base & L & H & Base & L & H \\
\hline
""" + "\n".join(body) + r"""
\hline\hline
\end{tabularx}""" + end_mark + r"""
\begin{tablenotes}[para,flushleft]
\footnotesize
\item \textit{Notes:} """ + note + r"""
\end{tablenotes}
\end{threeparttable}
\end{table}""")
