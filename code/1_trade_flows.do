import delimited "data/raw/states.csv", clear varnames(1)
keep state fips
rename (state fips) (origin dms_origst)
tempfile origins
save `origins'
rename (origin dms_origst) (destination dms_destst)
tempfile destinations
save `destinations'

import delimited "data/raw/faf/faf5_2017.csv", clear varnames(1)
summarize current_value_2022, meanonly
scalar nominal_2022 = r(sum)
summarize value_2022, meanonly
scalar deflator = nominal_2022 / r(sum)
display "FAF5 2017-to-2022 dollar deflator: " %9.6f deflator
collapse (sum) trade = value_2017, by(dms_origst dms_destst)
generate year = 2017
tempfile faf2017
save `faf2017'

import delimited "data/raw/faf/faf5_2012.csv", clear varnames(1)
collapse (sum) trade = value_2012, by(dms_origst dms_destst)
generate year = 2012
append using `faf2017'
replace trade = trade * deflator
tempfile faf2012_2017
save `faf2012_2017'

import delimited "data/raw/faf/faf6_2022.csv", clear varnames(1)
collapse (sum) trade = value_2022, by(dms_origst dms_destst)
generate year = 2022
append using `faf2012_2017'

merge m:1 dms_origst using `origins', assert(match) nogenerate
merge m:1 dms_destst using `destinations', assert(match) nogenerate
fillin year origin destination
replace trade = 0 if _fillin
keep year origin destination trade
sort year origin destination
tabstat trade, by(year) statistics(n sum) format(%16.0fc)
export delimited using "data/derived/trade_flows.csv", replace
