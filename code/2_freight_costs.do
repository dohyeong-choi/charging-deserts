import delimited "data/raw/states.csv", clear varnames(1)
keep state atri_region
tempfile regions
save `regions'

import delimited "data/raw/eia_electricity_prices_2022.csv", clear varnames(1) asdouble
merge 1:1 state using `regions', assert(match) nogenerate
collapse (mean) electricity_price = price, by(atri_region)
tempfile electricity
save `electricity'

import delimited "data/raw/atri_regional_costs_2022.csv", clear varnames(1) asdouble
merge 1:1 atri_region using `electricity', assert(match) nogenerate
generate double rate_fuel = fuel + lease + maintenance + insurance + permits + tires + tolls + wages + benefits
generate double energy_ev = 2 * electricity_price / 100
generate double rate_ev_dr = rate_fuel - fuel + energy_ev
generate double rate_ev_ndr = rate_ev_dr - (wages + benefits)
keep atri_region electricity_price energy_ev fuel wages benefits rate_fuel rate_ev_dr rate_ev_ndr
order atri_region electricity_price energy_ev fuel wages benefits rate_fuel rate_ev_dr rate_ev_ndr
list, noobs abbreviate(20)
export delimited using "data/derived/freight_rates.csv", replace
tempfile rates
save `rates'

import delimited "data/raw/route_distances.csv", clear varnames(1)
rename origin state
merge m:1 state using `regions', assert(match) nogenerate
merge m:1 atri_region using `rates', assert(match) keepusing(rate_fuel rate_ev_dr rate_ev_ndr) nogenerate
rename state origin
generate double cost_fuel = dist_fuel * rate_fuel
foreach s in real pop str {
    generate double cost_`s' = dist_`s' * rate_ev_dr
}
generate double cost_auto = dist_str * rate_ev_ndr
foreach s in real pop str auto {
    generate byte status_`s' = cond(missing(cost_`s'), 0, cond(cost_`s' < cost_fuel, 2, 1))
}
keep origin destination dist_fuel dist_real dist_pop dist_str cost_fuel cost_real cost_pop cost_str cost_auto status_real status_pop status_str status_auto
order origin destination dist_fuel dist_real dist_pop dist_str cost_fuel cost_real cost_pop cost_str cost_auto status_real status_pop status_str status_auto
sort origin destination
tabulate status_real if origin != destination
tabulate status_pop if origin != destination
tabulate status_str if origin != destination
tabulate status_auto if origin != destination
export delimited using "data/derived/freight_costs.csv", replace
