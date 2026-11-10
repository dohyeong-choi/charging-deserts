import delimited "data/raw/states.csv", clear varnames(1)
keep fips
tempfile fips48
save `fips48'

capture mkdir "data/raw/faf"

import delimited "data/raw/faf_original/FAF5.7.1_Reprocessed_1997-2012_State.csv", clear varnames(1) stringcols(_all)
keep if dms_mode == "1" & trade_type == "1"
generate fips = real(dms_origst)
merge m:1 fips using `fips48', keep(match) nogenerate
replace fips = real(dms_destst)
merge m:1 fips using `fips48', keep(match) nogenerate
keep dms_origst dms_destst sctg2 value_2012
sort dms_origst dms_destst sctg2
export delimited using "data/raw/faf/faf5_2012.csv", replace

import delimited "data/raw/faf_original/FAF5.7.1_State.csv", clear varnames(1) stringcols(_all)
keep if dms_mode == "1" & trade_type == "1"
generate fips = real(dms_origst)
merge m:1 fips using `fips48', keep(match) nogenerate
replace fips = real(dms_destst)
merge m:1 fips using `fips48', keep(match) nogenerate
keep dms_origst dms_destst sctg2 dist_band value_2017 value_2022 current_value_2022
sort dms_origst dms_destst sctg2 dist_band
export delimited using "data/raw/faf/faf5_2017.csv", replace

import delimited "data/raw/faf_original/FAF6.0_State.csv", clear varnames(1) stringcols(_all)
keep if dms_mode == "1" & trade_type == "1"
generate fips = real(dms_origst)
merge m:1 fips using `fips48', keep(match) nogenerate
replace fips = real(dms_destst)
merge m:1 fips using `fips48', keep(match) nogenerate
keep dms_origst dms_destst sctg2 value_2022
sort dms_origst dms_destst sctg2
export delimited using "data/raw/faf/faf6_2022.csv", replace
