# synth_telemetry.tcl -- opt-in step telemetry for ORFS scripts/synth.tcl
#
# Needs util.tcl's env_var_* helpers). With SYNTH_TELEMETRY unset, every tel:: proc is a
# no-op and tel::synth is a straight pass-through to synth.
#
#   SYNTH_TELEMETRY=1       
#   SYNTH_TELEMETRY_STAT=1  for statjson/


namespace eval tel {
    variable enabled 0
    variable stats 0
    variable serial 0
    variable started 0
    variable dir ""
}

proc tel::init {} {
    variable enabled
    variable stats
    variable serial
    variable started
    variable dir
    set enabled [env_var_equals SYNTH_TELEMETRY 1]
    if {!$enabled} { return }
    set stats [env_var_equals SYNTH_TELEMETRY_STAT 1]
    set serial 0
    set started [clock microseconds]
    set dir [file join $::env(REPORTS_DIR) telemetry [format "%s-%d" [clock format [clock seconds] -format %Y%m%dT%H%M%S] [pid]]]
    file mkdir $dir
    if {$stats} { file mkdir [file join $dir stat] }
    set f [open [file join $dir steps.tsv] w]
    puts $f "order\tpass\tstatus\tstart_ms\tduration_ms\trss_kb"
    close $f
    puts "Yosys telemetry: $dir"
}

proc tel::rss {} {
    if {[file readable /proc/self/status]} {
        set f [open /proc/self/status]
        set body [read $f]
        close $f
        if {[regexp -line {^VmRSS:\s+(\d+)} $body -> kb]} { return $kb }
    } elseif {![catch {exec ps -o rss= -p [pid]} kb]} {
        return [string trim $kb]
    }
    return -1
}

# Pass a Tcl script as the second argument. Keeps all exceptions and return options.
proc tel::run {name script} {
    variable enabled
    variable stats
    variable serial
    variable started
    variable dir
    if {!$enabled} { return [uplevel 1 $script] }

    set n [incr serial]
    set start [clock microseconds]
    set code [catch {uplevel 1 $script} result options]
    set end [clock microseconds]
    set status [expr {$code == 0 ? "ok" : "failed"}]
    set label [string map [list "\t" _ "\n" _ "\r" _] $name]
    set f [open [file join $dir steps.tsv] a]
    puts $f [join [list $n $label $status \
        [format %.3f [expr {($start - $started)/1000.0}]] \
        [format %.3f [expr {($end - $start)/1000.0}]] [rss]] "\t"]
    close $f
    if {$code == 0 && $stats} {
        set safe [regsub -all {[^[:alnum:]_.-]} $name _]
        set path [file join $dir stat [format "%03d_%s.json" $n $safe]]
        if {[catch {::tee -q -o $path stat -json} err]} {
            puts stderr "telemetry: stat after $name failed: $err"
        }
    }
    return -options $options $result
}

proc tel::finish {} {
    variable enabled
    variable started
    variable serial
    if {!$enabled} { return }
    puts [format "Yosys telemetry: %d timed steps; %.1f ms total" \
        $serial [expr {([clock microseconds] - $started)/1000.0}]]
    set enabled 0
}
