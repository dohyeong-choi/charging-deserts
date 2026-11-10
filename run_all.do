clear all
set more off
set type float
version 17

foreach package in ftools reghdfe ppmlhdfe ge_gravity2 {
    capture which `package'
    if _rc ssc install `package'
}

foreach folder in "data/derived" "output" "output/logs" "output/tables" "output/figures" {
    capture mkdir "`folder'"
}

foreach step in 1_trade_flows 2_freight_costs 3_gravity 4_text_numbers {
    log using "output/logs/`step'.log", text replace nomsg
    do "code/`step'.do"
    log close
}
