# Explicit expansion of Yosys generic `synth` for individually timed passes.
# Keeps ORFS invocation sites/arguments unchanged: call tel::synth instead of synth.
proc tel::synth {args} {
    variable enabled
    if {!$enabled} { return [::synth {*}$args] }

    set from begin
    set until end
    set flatten 0
    set hieropt 0
    set nofsm 0
    set noalumacc 0
    set noshare 0
    set noabc 0
    set booth 0
    set arith_tree 0
    set nordff 0
    set no_rw_check 0
    set top ""
    set auto_top 0
    set encfile ""
    set latch_policy ""
    set extra_maps {}
    set lut ""

    # Parse the invocation, not a second independently configured pipeline.
    for {set i 0} {$i < [llength $args]} {incr i} {
        set arg [lindex $args $i]
        switch -- $arg {
            -flatten - -hieropt - -nofsm - -noalumacc - -noshare - -noabc - -booth - -arith_tree - -nordff - -no-rw-check - -auto-top {
                set [string map {- _} [string range $arg 1 end]] 1
            }
            -top - -encfile - -latches - -extra-map - -lut - -run {
                if {[incr i] >= [llength $args]} { error "synth: missing value for $arg" }
                set value [lindex $args $i]
                switch -- $arg {
                    -top {set top $value}
                    -encfile {set encfile $value}
                    -latches {set latch_policy $value}
                    -extra-map {lappend extra_maps $value}
                    -lut {set lut $value}
                    -run {
                        if {![regexp {^([^:]*):([^:]*)$} $value -> a b]} {
                            error "synth: unsupported -run '$value' (expected from:to)"
                        }
                        if {$a ne ""} {set from $a}
                        if {$b ne ""} {set until $b}
                    }
                }
            }
            default {error "expanded synth: unsupported option '$arg'"}
        }
    }
    # The Yosys `-run` stage end is exclusive for these ORFS invocations.
    set labels {begin coarse fine check end}
    set first [lsearch -exact $labels $from]
    set last [lsearch -exact $labels $until]
    if {$first < 0 || $last < 0 || $first >= $last} {error "synth: invalid -run $from:$until"}
    if {$lut ne ""} {error "expanded synth: -lut not implemented; use stock synth"}
    if {$nordff} {error "expanded synth: -nordff not verified; use stock synth"}
    if {$no_rw_check} {error "expanded synth: -no-rw-check not verified; use stock synth"}
    # Keep C++ synth option-dependent behavior explicit; don't guess for unsupported modes.
    if {$first <= 0 && 0 < $last} {
        if {$top ne ""} {
            tel::run begin.hierarchy [list ::hierarchy -check -top $top]
        } elseif {$auto_top || $flatten} {
            tel::run begin.hierarchy {::hierarchy -check -auto-top}
        } else {
            tel::run begin.hierarchy {::hierarchy -check}
        }
    }
    if {$first <= 1 && 1 < $last} {
        if {$latch_policy ne ""} {
            tel::run coarse.proc [list ::yosys proc -latches $latch_policy]
        } else {
            tel::run coarse.proc {::yosys proc}
        }
        tel::run coarse.check_1 {::check}
        if {$flatten} {tel::run coarse.flatten {::flatten}}
        tel::run coarse.opt_expr {::opt_expr}
        tel::run coarse.check_2 {::check}
        tel::run coarse.opt_clean_1 {::opt_clean}
        tel::run coarse.opt_1 {::opt -nodffe -nosdff}
        if {!$nofsm} {
            if {$encfile ne ""} {tel::run coarse.fsm [list ::fsm -encfile $encfile]} else {tel::run coarse.fsm {::fsm}}
        }
        if {$hieropt} {tel::run coarse.opt_2 {::opt -hier}} else {tel::run coarse.opt_2 {::opt}}
        tel::run coarse.wreduce {::wreduce}
        tel::run coarse.peepopt {::peepopt}
        tel::run coarse.opt_clean_2 {::opt_clean}
        if {$booth} {tel::run coarse.booth {::booth}}
        if {!$noalumacc} {tel::run coarse.alumacc {::alumacc}}
        if {$arith_tree} {tel::run coarse.arith_tree {::arith_tree}}
        if {!$noshare} {tel::run coarse.share {::share}}
        if {$hieropt} {tel::run coarse.opt_3 {::opt -hier}} else {tel::run coarse.opt_3 {::opt}}
        tel::run coarse.memory {::memory -nomap}
        tel::run coarse.opt_clean_3 {::opt_clean}
    }
    if {$first <= 2 && 2 < $last} {
        if {$hieropt} {tel::run fine.opt_1 {::opt -fast -full -hier}} else {tel::run fine.opt_1 {::opt -fast -full}}
        tel::run fine.memory_map {::memory_map}
        tel::run fine.opt_2 {::opt -full}
        if {[llength $extra_maps]} {
            set maps [list -map +/techmap.v]
            foreach m $extra_maps {lappend maps -map $m}
            tel::run fine.techmap [list ::techmap {*}$maps]
        } else {
            tel::run fine.techmap {::techmap}
        }
        if {$hieropt} {tel::run fine.opt_3 {::opt -fast -hier}} else {tel::run fine.opt_3 {::opt -fast}}
        if {!$noabc} {
            tel::run fine.abc {::abc}
            tel::run fine.opt_4 {::opt -fast}
        }
    }
    if {$first <= 3 && 3 < $last} {
        tel::run check.hierarchy {::hierarchy -check}
        tel::run check.stat {::stat}
        tel::run check.check {::check}
    }
}
