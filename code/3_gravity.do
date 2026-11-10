tempfile undirected contiguity costs baseline expenditure states_all pairs_all exports imports new

import delimited "data/raw/contiguity.csv", clear varnames(1)
save `undirected'
rename (state1 state2) (state2 state1)
append using `undirected'
rename (state1 state2) (origin destination)
generate byte contiguous = 1
save `contiguity'

import delimited "data/derived/freight_costs.csv", clear varnames(1)
save `costs'

import delimited "data/derived/trade_flows.csv", clear varnames(1) asdouble
merge m:1 origin destination using `costs', assert(match) keepusing(cost_fuel) nogenerate
merge m:1 origin destination using `contiguity', keep(master match) nogenerate
replace contiguous = 0 if missing(contiguous)
generate byte intrastate = origin == destination
sort year origin destination
export delimited year origin destination trade cost_fuel contiguous intrastate using "data/derived/gravity_sample.csv", replace

generate ln_cost = ln(cost_fuel)
egen exporter_year = group(origin year)
egen importer_year = group(destination year)
egen pair = group(origin destination)
ppmlhdfe trade ln_cost contiguous intrastate, absorb(exporter_year importer_year) cluster(pair)

scalar beta = _b[ln_cost]
scalar nobs = e(N)
scalar pseudo_r2 = e(r2_p)
scalar clusters = e(N_clust)
matrix estimates = (_b[ln_cost], _se[ln_cost] \ _b[contiguous], _se[contiguous] \ _b[intrastate], _se[intrastate])

clear
svmat double estimates
rename (estimates1 estimates2) (coef se)
generate term = ""
replace term = "ln_cost" in 1
replace term = "contiguous" in 2
replace term = "intrastate" in 3
generate nobs = scalar(nobs)
generate double pseudo_r2 = scalar(pseudo_r2)
generate clusters = scalar(clusters)
order term coef se nobs pseudo_r2 clusters
export delimited using "data/derived/gravity_estimates.csv", replace

import delimited "data/derived/trade_flows.csv", clear varnames(1) asdouble
keep if year == 2022
drop year
merge 1:1 origin destination using `costs', assert(match) keepusing(cost_fuel cost_real cost_pop cost_str cost_auto) nogenerate
save `baseline'
collapse (sum) expenditure = trade, by(destination)
rename destination state
save `expenditure'

clear
save `states_all', emptyok
save `pairs_all', emptyok

foreach theta in 4.14 2.79 4.46 {
    foreach s in real pop str auto {
        use `baseline', clear
        generate cost_bln = cost_fuel
        generate cost_cfl = min(cost_`s', cost_fuel)
        generate dlncost = ln(cost_cfl) - ln(cost_bln)
        generate partial = beta * dlncost
        ge_gravity2 origin destination trade partial, theta(`theta') psi(0) gen_X(trade_cf) gen_p(p_hat) gen_P(P_hat) results
        matrix results = e(results)
        local states : rownames results

        egen exports_bln = total(trade) if origin != destination, by(origin)
        egen exports_cfl = total(trade_cf) if origin != destination, by(origin)
        generate exports_diff = exports_cfl / p_hat - exports_bln
        generate own_P = P_hat if origin == destination
        egen P_destination = max(own_P), by(destination)
        egen imports_bln = total(trade) if origin != destination, by(destination)
        egen imports_cfl = total(trade_cf) if origin != destination, by(destination)
        generate imports_diff = imports_cfl / P_destination - imports_bln

        preserve
        keep if origin != destination
        collapse (first) exports_diff, by(origin)
        rename origin state
        save `exports', replace
        restore
        preserve
        keep if origin != destination
        collapse (first) imports_diff, by(destination)
        rename destination state
        save `imports', replace
        restore

        keep origin destination trade trade_cf
        generate double theta = `theta'
        generate scenario = "`s'"
        save `new', replace
        use `pairs_all', clear
        append using `new'
        save `pairs_all', replace

        clear
        svmat double results, names(col)
        generate state = ""
        forvalues i = 1/`=rowsof(results)' {
            replace state = word("`states'", `i') in `i'
        }
        keep state Exports Imports Welfare
        rename (Exports Imports Welfare) (exports_pct imports_pct welfare_pct)
        merge 1:1 state using `exports', assert(match) nogenerate
        merge 1:1 state using `imports', assert(match) nogenerate
        merge 1:1 state using `expenditure', assert(match) nogenerate
        generate double welfare_diff = welfare_pct / 100 * expenditure
        drop expenditure
        generate double theta = `theta'
        generate scenario = "`s'"
        save `new', replace
        use `states_all', clear
        append using `new'
        save `states_all', replace
    }
}

use `states_all', clear
order theta scenario state exports_pct imports_pct welfare_pct exports_diff imports_diff welfare_diff
export delimited using "data/derived/counterfactual_states.csv", replace

use `pairs_all', clear
order theta scenario origin destination trade trade_cf
export delimited using "data/derived/counterfactual_pairs.csv", replace
