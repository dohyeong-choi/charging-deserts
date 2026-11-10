tempfile states westorigin trade22 expenditure exporters pairs edges labels systems welfare cfpairs owncut distances partners

local name_real "Existing Charging Network"
local name_pop "Population-Center Expansion"
local name_str "Strategic Network Expansion"
local name_auto "Strategic Network + Autonomy"

capture program drop put
program define put
    args label value fmt
    if "`fmt'" == "" local fmt "%12.0fc"
    local text = strtrim(string(`value', "`fmt'"))
    file write numbers `"    `label'"' _col(102) `"`text'"' _n
end

capture program drop puttext
program define puttext
    args label text
    file write numbers `"    `label'"' _col(102) `"`text'"' _n
end

import delimited "data/raw/states.csv", clear varnames(1)
forvalues i = 1/`=_N' {
    local id = state[`i']
    local st_`id' = name[`i']
}
keep state name west strategic_host
save `states'
keep state west
rename state origin
save `westorigin'

import delimited "data/derived/trade_flows.csv", clear varnames(1) asdouble
keep if year == 2022
drop year
save `trade22'
collapse (sum) expenditure = trade, by(destination)
rename destination state
save `expenditure'
use `trade22', clear
keep if origin == destination
keep origin trade
rename (origin trade) (state own_trade)
merge 1:1 state using `expenditure', assert(match) nogenerate
generate double outside_share = 1 - own_trade / expenditure
save `expenditure', replace

import delimited "data/derived/freight_costs.csv", clear varnames(1) asdouble
keep if origin != destination
merge 1:1 origin destination using `trade22', keep(match) nogenerate
foreach side in origin destination {
    rename `side' state
    merge m:1 state using `states', assert(match) keepusing(name west strategic_host) nogenerate
    rename (state name west strategic_host) (`side' name_`side' west_`side' host_`side')
}
generate byte cross = west_origin != west_destination
foreach s in real pop str auto {
    generate byte feasible_`s' = status_`s' > 0
    generate byte adopt_`s' = status_`s' == 2
    generate double tau_`s' = min(cost_`s', cost_fuel)
}
generate byte new = feasible_str & !feasible_pop
generate byte idaho = origin == "IDAHO" | destination == "IDAHO"
preserve
collapse (sum) partner_exports = trade, by(origin)
rename origin destination
save `exporters'
restore
merge m:1 destination using `exporters', assert(match) nogenerate
foreach s in real pop str auto {
    egen double reach_`s' = total(partner_exports * feasible_`s' / 1e6), by(origin)
    egen double adopted_`s' = total(partner_exports * adopt_`s' / 1e6), by(origin)
    egen partners_`s' = total(feasible_`s'), by(origin)
}
egen east_partners_pop = total(feasible_pop * !west_destination), by(origin)
egen west_partners_pop = total(feasible_pop * west_destination), by(origin)
egen byte first = tag(origin)
save `pairs'

keep if feasible_real
keep origin destination
save `edges'
rename (origin destination) (destination origin)
append using `edges'
duplicates drop
save `edges', replace
keep origin
duplicates drop
rename origin state
generate system = _n
save `labels'
local changed = 1
while `changed' {
    use `edges', clear
    rename origin state
    merge m:1 state using `labels', assert(match) nogenerate
    collapse (min) neighbor = system, by(destination)
    rename destination state
    merge 1:1 state using `labels', assert(match) nogenerate
    count if neighbor < system
    local changed = r(N) > 0
    replace system = min(system, neighbor)
    drop neighbor
    save `labels', replace
}
merge 1:1 state using `states', keep(match) keepusing(name west) nogenerate
egen system_west = max(west), by(system)
save `labels', replace
keep state system_west
rename state origin
save `systems'

import delimited "data/derived/counterfactual_states.csv", clear varnames(1) asdouble
merge m:1 state using `expenditure', assert(match) nogenerate
merge m:1 state using `states', assert(match) nogenerate
save `welfare'
keep if theta == 4.14
foreach s in real pop str auto {
    summarize welfare_pct [aweight = expenditure] if scenario == "`s'", meanonly
    scalar W_`s' = round(r(mean), 0.001)
}
scalar inc_a = W_pop - W_real
scalar inc_b = W_str - W_pop
scalar inc_c = W_auto - W_str

import delimited "data/derived/counterfactual_pairs.csv", clear varnames(1) asdouble
keep if theta == 4.14
keep scenario origin destination trade_cf
reshape wide trade_cf, i(origin destination) j(scenario) string
save `cfpairs'

file open numbers using "output/text_numbers.txt", write replace text

file write numbers "Introduction" _n
put "Nationwide welfare gain, Existing Charging Network to Population-Center Expansion (pp)" "scalar(inc_a)" "%9.3f"
put "Strategic Network Expansion over Population-Center Expansion (pp)" "scalar(inc_b)" "%9.3f"
put "Strategic Network + Autonomy over Strategic Network Expansion (pp)" "scalar(inc_c)" "%9.1f"
put "Population-center gain relative to the Interstate Highway System value of 3.6 percent (%)" "100 * scalar(inc_a) / 3.6" "%9.0f"
put "Population-center gain relative to the Interstate Highway System value of 1.1 percent (%)" "100 * scalar(inc_a) / 1.1" "%9.0f"
put "Strategic-station gain relative to the Interstate Highway System value of 1.1 percent (%)" "100 * scalar(inc_b) / 1.1" "%9.1f"
put "Autonomy gain relative to the Interstate Highway System value of 3.6 percent (times)" "scalar(inc_c) / 3.6" "%9.1f"
put "Autonomy gain relative to the Interstate Highway System value of 1.1 percent (times)" "scalar(inc_c) / 1.1" "%9.1f"

file write numbers _n "Section 3" _n
import delimited "data/derived/freight_costs.csv", clear varnames(1) asdouble
keep origin destination dist_fuel
save `distances'
import delimited "data/derived/gravity_sample.csv", clear varnames(1) asdouble
merge m:1 origin destination using `distances', assert(match) nogenerate
summarize trade if intrastate
put "Mean intrastate trade flow (USD billion)" "r(mean) / 1000" "%9.1f"
summarize dist_fuel if intrastate
put "Mean intrastate distance (miles)" "r(mean)" "%9.0f"
summarize trade if !intrastate
put "Mean interstate trade flow (USD billion)" "r(mean) / 1000" "%9.1f"
summarize dist_fuel if !intrastate
put "Mean interstate distance (miles)" "r(mean)" "%9.0fc"

import delimited "data/derived/freight_rates.csv", clear varnames(1) asdouble
generate double energy_ratio = 100 * energy_ev / fuel
generate double advantage_dr = 100 * (fuel - energy_ev) / rate_fuel
generate double breakeven = 100 * (1 / (1 - advantage_dr / 100) - 1)
generate double advantage_ndr = 100 * (fuel - energy_ev + wages + benefits) / rate_fuel
summarize energy_ratio
put "Electric energy cost as share of diesel fuel cost, lowest region (%)" "r(min)" "%9.0f"
put "Electric energy cost as share of diesel fuel cost, highest region (%)" "r(max)" "%9.0f"
summarize advantage_dr
scalar adv_dr = r(mean)
put "Per-mile cost advantage of driver-operated electric trucks, average of regions (%)" "r(mean)" "%9.0f"
put "Per-mile cost advantage of driver-operated electric trucks, lowest region (%)" "r(min)" "%9.0f"
put "Per-mile cost advantage of driver-operated electric trucks, highest region (%)" "r(max)" "%9.0f"
summarize breakeven
put "Break-even detour relative to the diesel route, lowest region (%)" "r(min)" "%9.1f"
put "Break-even detour relative to the diesel route, highest region (%)" "r(max)" "%9.1f"
summarize advantage_ndr
put "Per-mile cost advantage of autonomous electric trucks, average of regions (%)" "r(mean)" "%9.0f"
put "Ratio of the autonomous to the driver-operated advantage" "r(mean) / scalar(adv_dr)" "%9.1f"

file write numbers _n "Section 5.1" _n
import delimited "data/derived/gravity_estimates.csv", clear varnames(1) asdouble
put "Coefficient on log freight cost" "coef[1]" "%9.3f"
put "Coefficient on contiguity" "coef[2]" "%9.3f"
put "Trade increase implied by contiguity (%)" "100 * (exp(coef[2]) - 1)" "%9.0f"
put "Coefficient on intrastate trade" "coef[3]" "%9.3f"
put "Trade increase implied by intrastate trade (times)" "exp(coef[3]) - 1" "%9.1f"

file write numbers _n "Section 5.2" _n
use `pairs', clear
count
put "Interstate origin-destination pairs" "r(N)"
count if cross
put "East-West pairs" "r(N)"
preserve
use `states', clear
count if west
put "Western states" "r(N)"
count if !west
put "States east of the Rockies" "r(N)"
restore
count if feasible_real
put "Charging-feasible pairs, `name_real'" "r(N)"
count if cross & feasible_real
put "Feasible East-West pairs, `name_real'" "r(N)"
preserve
use `labels', clear
count
put "States in a charging-feasible pair, `name_real'" "r(N)"
egen byte system_tag = tag(system)
count if system_tag
put "Disjoint charging-feasible systems, `name_real'" "r(N)"
levelsof name if system_west, local(list) clean separate(", ")
puttext "Western system" "`list'"
count if !system_west
put "States in the eastern system" "r(N)"
restore
count if feasible_pop
put "Charging-feasible pairs, `name_pop'" "r(N)"
count if cross & feasible_pop
put "Feasible East-West pairs, `name_pop'" "r(N)"
count if first & !west_origin & east_partners_pop == 36 & west_partners_pop == 0
put "Eastern states reaching all 36 other eastern states, `name_pop'" "r(N)"
count if feasible_pop & (inlist(origin, "IDAHO", "NEW_MEXICO") | inlist(destination, "IDAHO", "NEW_MEXICO"))
put "Feasible pairs involving Idaho or New Mexico, `name_pop'" "r(N)"
count if first & west_origin & !inlist(origin, "IDAHO", "NEW_MEXICO") & west_partners_pop == 8 & east_partners_pop == 0
put "Other western states reaching exactly the other eight, `name_pop'" "r(N)"
count if feasible_str
put "Charging-feasible pairs, `name_str'" "r(N)"
count if cross & feasible_str
put "Feasible East-West pairs, `name_str'" "r(N)"
count if first & origin != "IDAHO" & partners_str == 46
put "States other than Idaho reaching all 46 other such states, `name_str'" "r(N)"
count if !feasible_str & !idaho
put "Infeasible pairs not involving Idaho, `name_str'" "r(N)"

file write numbers _n "Section 5.3" _n
summarize trade, meanonly
scalar interstate_total = r(sum)
put "Baseline interstate truck-served exports (USD trillion)" "scalar(interstate_total) / 1e6" "%9.1f"
preserve
keep if first
merge 1:1 origin using `systems', keep(master match)
generate byte in_system = _merge == 3
summarize reach_real if in_system & !system_west
put "Connected reach in the eastern system, lowest state (USD trillion)" "r(min)" "%9.2f"
put "Connected reach in the eastern system, highest state (USD trillion)" "r(max)" "%9.2f"
summarize reach_real if in_system & system_west
put "Connected reach in the western system, lowest state (USD trillion)" "r(min)" "%9.2f"
put "Connected reach in the western system, highest state (USD trillion)" "r(max)" "%9.2f"
count if partners_real == 0
put "States that reach no other state, `name_real'" "r(N)"
summarize reach_pop if !west_origin
put "Connected reach of eastern states, lowest, `name_pop' (USD trillion)" "r(min)" "%9.2f"
levelsof name_origin if west_origin & partners_real == 0 & partners_pop > 0, local(list) clean separate(", ")
puttext "Western states connected for the first time, `name_pop'" "`list'"
summarize reach_pop if west_origin & !inlist(origin, "IDAHO", "NEW_MEXICO")
put "Connected reach of the nine western states, highest, `name_pop' (USD trillion)" "r(max)" "%9.2f"
summarize adopted_pop if west_origin
put "Adopted reach of western states, highest, `name_pop' (USD trillion)" "r(max)" "%9.2f"
summarize adopted_pop if !west_origin
put "Adopted reach of eastern states, lowest, `name_pop' (USD trillion)" "r(min)" "%9.2f"
restore
count if adopt_real
put "Adopting pairs, `name_real'" "r(N)"
foreach s in real pop str auto {
    summarize trade if feasible_`s', meanonly
    put "Feasible share of interstate trade, `name_`s'' (%)" "100 * r(sum) / scalar(interstate_total)" "%9.1f"
    summarize trade if adopt_`s', meanonly
    put "Adopting share of interstate trade, `name_`s'' (%)" "100 * r(sum) / scalar(interstate_total)" "%9.1f"
}
foreach pair in "WISCONSIN ALABAMA real" "ALABAMA KANSAS pop" {
    tokenize `pair'
    summarize dist_fuel if origin == "`1'" & destination == "`2'", meanonly
    scalar d0 = r(mean)
    summarize dist_`3' if origin == "`1'" & destination == "`2'", meanonly
    scalar d1 = r(mean)
    put "`st_`1''-`st_`2'' diesel route (miles)" "scalar(d0)" "%9.0fc"
    put "`st_`1''-`st_`2'' charging-feasible route, `name_`3'' (miles)" "scalar(d1)" "%9.0fc"
    put "`st_`1''-`st_`2'' detour relative to the diesel route (%)" "100 * (scalar(d1) / scalar(d0) - 1)" "%9.0f"
    count if status_`3' == 1 & ((origin == "`1'" & destination == "`2'") | (origin == "`2'" & destination == "`1'"))
    put "`st_`1''-`st_`2'' directions feasible but on diesel, `name_`3''" "r(N)"
}

file write numbers _n "Section 5.4" _n
count if cross & !feasible_str
put "East-West pairs infeasible, `name_str'" "r(N)"
count if cross & !feasible_str & !idaho
put "Of which not involving Idaho" "r(N)"
count if feasible_str & idaho
put "Feasible pairs involving Idaho, `name_str'" "r(N)"
preserve
keep if first
generate double increase = reach_str - reach_pop
summarize increase if origin == "NEW_MEXICO"
put "Increase in connected reach of New Mexico (USD trillion)" "r(mean)" "%9.1f"
summarize increase
put "Largest increase in connected reach among all states (USD trillion)" "r(max)" "%9.1f"
summarize increase if west_origin & !inlist(origin, "IDAHO", "NEW_MEXICO")
put "Increase in connected reach of the other nine western states, lowest (USD trillion)" "r(min)" "%9.1f"
put "Increase in connected reach of the other nine western states, highest (USD trillion)" "r(max)" "%9.1f"
summarize reach_pop if origin == "WASHINGTON"
put "Connected reach of Washington, `name_pop' (USD trillion)" "r(mean)" "%9.1f"
summarize reach_str if origin == "WASHINGTON"
put "Connected reach of Washington, `name_str' (USD trillion)" "r(mean)" "%9.1f"
summarize adopted_pop if origin == "WASHINGTON"
put "Adopted reach of Washington, `name_pop' (USD trillion)" "r(mean)" "%9.1f"
summarize adopted_str if origin == "WASHINGTON"
put "Adopted reach of Washington, `name_str' (USD trillion)" "r(mean)" "%9.1f"
summarize adopted_auto if origin == "WASHINGTON"
put "Adopted reach of Washington, `name_auto' (USD trillion)" "r(mean)" "%9.1f"
restore
count if new
scalar n_new = r(N)
put "Pairs newly feasible under the `name_str'" "scalar(n_new)"
count if new & adopt_str
put "Of which adopting electric trucking" "r(N)"
put "Share adopting (%)" "100 * r(N) / scalar(n_new)" "%9.0f"
count if new & !adopt_str
scalar n_exc = r(N)
count if new & !adopt_str & (inlist(origin, "WASHINGTON", "OREGON", "MONTANA", "WYOMING") | inlist(destination, "WASHINGTON", "OREGON", "MONTANA", "WYOMING"))
put "Non-adopting new pairs involving Washington, Oregon, Montana, or Wyoming (%)" "100 * r(N) / scalar(n_exc)" "%9.0f"
summarize dist_fuel if origin == "MONTANA" & destination == "NEBRASKA", meanonly
scalar d0 = r(mean)
summarize dist_str if origin == "MONTANA" & destination == "NEBRASKA", meanonly
scalar d1 = r(mean)
put "Montana-Nebraska diesel route (miles)" "scalar(d0)" "%9.0fc"
put "Montana-Nebraska charging-feasible route, `name_str' (miles)" "scalar(d1)" "%9.0fc"
put "Montana-Nebraska detour relative to the diesel route (%)" "100 * (scalar(d1) / scalar(d0) - 1)" "%9.0f"
count if new & status_str == 1 & ((origin == "MONTANA" & destination == "NEBRASKA") | (origin == "NEBRASKA" & destination == "MONTANA"))
put "Montana-Nebraska directions newly feasible but on diesel, `name_str'" "r(N)"
count if new & adopt_auto
put "New pairs adopting electric trucking, `name_auto'" "r(N)"
count if new & !adopt_auto
put "New pairs not adopting, `name_auto'" "r(N)"
count if new & !adopt_auto & (origin == "NORTH_DAKOTA" | destination == "NORTH_DAKOTA")
put "Of which involving North Dakota" "r(N)"
summarize dist_fuel if origin == "MONTANA" & destination == "NORTH_DAKOTA", meanonly
scalar d0 = r(mean)
summarize dist_str if origin == "MONTANA" & destination == "NORTH_DAKOTA", meanonly
scalar d1 = r(mean)
put "Montana-North Dakota diesel route (miles)" "scalar(d0)" "%9.0fc"
put "Montana-North Dakota charging-feasible route (miles)" "scalar(d1)" "%9.0fc"
put "Montana-North Dakota ratio of charging-feasible to diesel route" "scalar(d1) / scalar(d0)" "%9.1f"
count if status_auto == 1 & ((origin == "MONTANA" & destination == "NORTH_DAKOTA") | (origin == "NORTH_DAKOTA" & destination == "MONTANA"))
put "Montana-North Dakota directions feasible but on diesel, `name_auto'" "r(N)"

file write numbers _n "Section 5.5" _n
summarize status_pop if origin == "CALIFORNIA" & destination == "NEW_YORK", meanonly
put "California-New York route status, `name_pop'" "r(mean)" "%9.0f"
summarize status_str if origin == "CALIFORNIA" & destination == "NEW_YORK", meanonly
put "California-New York route status, `name_str'" "r(mean)" "%9.0f"
summarize trade if new, meanonly
scalar new_trade = r(sum)
put "Baseline trade on newly feasible pairs (USD billion)" "scalar(new_trade) / 1000" "%9.0f"
put "Share of baseline interstate trade (%)" "100 * scalar(new_trade) / scalar(interstate_total)" "%9.1f"
summarize trade if new & !host_origin & !host_destination, meanonly
put "Newly feasible trade between two non-host states (%)" "100 * r(sum) / scalar(new_trade)" "%9.1f"
count if new & !host_origin & !host_destination
put "Newly feasible pairs between two non-host states (%)" "100 * r(N) / scalar(n_new)" "%9.1f"
summarize trade if new & host_origin, meanonly
put "Newly feasible trade originating in the four host states (%)" "100 * r(sum) / scalar(new_trade)" "%9.1f"
summarize trade if new & origin == "CALIFORNIA", meanonly
scalar ca_new = r(sum)
put "Newly feasible trade originating in California (%)" "100 * scalar(ca_new) / scalar(new_trade)" "%9.1f"
preserve
generate double new_exports = trade * new
collapse (sum) trade new_exports, by(origin name_origin)
gsort -new_exports
puttext "State originating the largest share of newly feasible trade" "`=name_origin[1]'"
gsort -trade
puttext "Largest exporting state" "`=name_origin[1]'"
put "Largest exporting state's share of interstate exports (%)" "100 * trade[1] / scalar(interstate_total)" "%9.1f"
restore
summarize partners_pop if origin == "CALIFORNIA" & first
put "States reachable from California, `name_pop'" "r(mean)"
summarize trade if origin == "CALIFORNIA", meanonly
put "California's interstate exports newly connected (%)" "100 * scalar(ca_new) / r(sum)" "%9.1f"
count if new & idaho
put "Newly feasible pairs involving Idaho" "r(N)"

file write numbers _n "Section 5.6" _n
use `pairs', clear
keep if first
keep origin partners_real partners_pop partners_str
rename origin state
save `partners'
use `pairs', clear
generate double wcut_a = trade * 100 * (tau_real - tau_pop) / tau_real
generate double wcut_b = trade * 100 * (tau_pop - tau_str) / tau_pop
summarize wcut_a, meanonly
scalar national_cut_a = r(sum) / scalar(interstate_total)
expand 2
bysort origin destination: generate state = cond(_n == 1, origin, destination)
collapse (sum) wcut_a wcut_b trade, by(state)
generate double own_cut_a = wcut_a / trade
generate double own_cut_b = wcut_b / trade
save `owncut'

use `welfare', clear
keep if theta == 4.14
keep scenario state name welfare_pct exports_pct imports_pct expenditure outside_share strategic_host
reshape wide welfare_pct exports_pct imports_pct, i(state) j(scenario) string
merge 1:1 state using `owncut', assert(match) keepusing(own_cut_a own_cut_b) nogenerate
merge 1:1 state using `partners', assert(match) nogenerate
generate double change_a = welfare_pctpop - welfare_pctreal
generate double change_b = welfare_pctstr - welfare_pctpop
generate double change_c = welfare_pctauto - welfare_pctstr
generate byte newly_connected = partners_real == 0 & partners_pop > 0

put "Transition (a): nationwide welfare gain (pp)" "scalar(inc_a)" "%9.3f"
count if newly_connected
put "States connected for the first time" "r(N)"
gsort -change_a
count if newly_connected in 1/10
put "Of the ten largest welfare increases, states connected for the first time" "r(N)"
levelsof name if change_a < 0, local(list) clean separate(", ")
puttext "States with welfare losses" "`list'"
foreach s in COLORADO IDAHO UTAH {
    summarize own_cut_a if state == "`s'", meanonly
    put "Trade-weighted fall in own freight costs, `st_`s'' (%)" "r(mean)" "%9.1f"
}
put "Trade-weighted fall in freight costs, all interstate pairs (%)" "scalar(national_cut_a)" "%9.1f"
preserve
use `pairs', clear
keep if origin == "UTAH"
gsort -trade
puttext "Utah's three largest interstate markets" "`=name_destination[1]', `=name_destination[2]', `=name_destination[3]'"
count if status_pop == 1 & inlist(destination, "CALIFORNIA", "NEVADA")
put "Utah's routes to California and Nevada that are feasible but remain on diesel" "r(N)"
use `pairs', clear
foreach pair in "OREGON CALIFORNIA" "CALIFORNIA NEVADA" {
    tokenize `pair'
    summarize tau_real if origin == "`1'" & destination == "`2'", meanonly
    scalar t0 = r(mean)
    summarize tau_pop if origin == "`1'" & destination == "`2'", meanonly
    put "Fall in the freight cost of `st_`1'' to `st_`2'' (%)" "100 * (scalar(t0) - r(mean)) / scalar(t0)" "%9.0f"
}
use `cfpairs', clear
foreach j in CALIFORNIA NEVADA {
    summarize trade_cfpop if origin == "UTAH" & destination == "`j'", meanonly
    scalar t1 = r(mean)
    summarize trade_cfreal if origin == "UTAH" & destination == "`j'", meanonly
    put "Change in Utah's shipments to `st_`j'' (%)" "100 * (scalar(t1) / r(mean) - 1)" "%9.2f"
}
restore

put "Transition (b): nationwide welfare gain (pp)" "scalar(inc_b)" "%9.3f"
gsort -change_b
puttext "Largest welfare increase" "`=name[1]'"
put "Welfare increase of that state (pp)" "change_b[1]" "%9.2f"
put "Export increase of that state (pp)" "exports_pctstr[1] - exports_pctpop[1]" "%9.1f"
puttext "Next five largest welfare increases" "`=name[2]', `=name[3]', `=name[4]', `=name[5]', `=name[6]'"
summarize partners_str if state == "WASHINGTON", meanonly
scalar wa = r(mean)
summarize partners_pop if state == "WASHINGTON", meanonly
put "Additional feasible partners of Washington" "scalar(wa) - r(mean)"
preserve
use `pairs', clear
count if origin == "WASHINGTON" & new & adopt_str
scalar wa_adopt = r(N)
restore
put "Of which adopting electric trucking" "scalar(wa_adopt)"
summarize own_cut_b if state == "WASHINGTON", meanonly
put "Trade-weighted fall in own freight costs, Washington (%)" "r(mean)" "%9.4f"
summarize change_b if state == "WASHINGTON", meanonly
put "Welfare change of Washington (pp)" "r(mean)" "%9.3f"
summarize change_b if state == "DELAWARE", meanonly
put "Welfare change of Delaware (pp)" "r(mean)" "%9.3f"
generate double gain_b = change_b / 100 * expenditure
summarize gain_b, meanonly
scalar gain_total = r(sum)
summarize gain_b if strategic_host, meanonly
put "Share of the aggregate welfare gain received by the four host states (%)" "100 * r(sum) / scalar(gain_total)" "%9.1f"
put "Share accruing elsewhere (%)" "100 - 100 * r(sum) / scalar(gain_total)" "%9.1f"
preserve
use `pairs', clear
keep if origin == "DELAWARE"
gsort -trade
local markets "`=destination[1]' `=destination[2]' `=destination[3]'"
puttext "Delaware's three largest interstate markets" "`=name_destination[1]', `=name_destination[2]', `=name_destination[3]'"
use `cfpairs', clear
merge m:1 origin using `westorigin', assert(match) nogenerate
generate double change = trade_cfstr - trade_cfpop
foreach j of local markets {
    summarize change if origin == "DELAWARE" & destination == "`j'", meanonly
    put "Change in Delaware's shipments to `st_`j'' (USD million)" "r(mean)" "%9.1f"
    summarize change if west & destination == "`j'" & origin != "`j'", meanonly
    put "Change in western states' shipments to `st_`j'' (USD million)" "r(sum)" "%9.1f"
}
restore

put "Transition (c): nationwide welfare gain (pp)" "scalar(inc_c)" "%9.3f"
levelsof name if change_c < 0, local(list) clean separate(", ")
puttext "States with welfare losses" "`list'"
summarize change_c if state != "IDAHO"
put "Smallest welfare increase among the other states (pp)" "r(min)" "%9.1f"
put "Largest welfare increase among the other states (pp)" "r(max)" "%9.1f"
foreach s in DELAWARE RHODE_ISLAND CALIFORNIA TEXAS {
    summarize change_c if state == "`s'", meanonly
    put "Welfare increase of `st_`s'' (pp)" "r(mean)" "%9.1f"
    summarize outside_share if state == "`s'", meanonly
    put "Share of expenditure sourced from other states, `st_`s''" "r(mean)" "%9.2f"
}
foreach s in real pop str auto {
    summarize welfare_pct`s' if state == "IDAHO", meanonly
    put "Welfare change of Idaho, `name_`s'' (%)" "r(mean)" "%9.2f"
}
count if state == "IDAHO" & exports_pctreal < 0 & exports_pctpop < 0 & exports_pctstr < 0 & exports_pctauto < 0 & imports_pctreal < 0 & imports_pctpop < 0 & imports_pctstr < 0 & imports_pctauto < 0
put "Idaho's exports and imports fall in all four scenarios (1 = yes)" "r(N)"

file close numbers
type "output/text_numbers.txt"
