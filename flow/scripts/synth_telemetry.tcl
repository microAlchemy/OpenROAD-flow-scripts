# synth_telemetry.tcl -- opt-in step telemetry for ORFS scripts/synth.tcl
#
# Sourced by synth.tcl right after synth_preamble.tcl (needs util.tcl's
# env_var_* helpers). With SYNTH_TELEMETRY unset, every tel:: proc is a
# no-op and tel::synth is a straight pass-through to sytnh.
#
#   SYNTH_TELEMETRY=1       
#   SYNTH_TELEMETRY_STAT=1  for statjson/


namespace eval tel {
  variable on 0
  variable stat 0
  variable split_ok 0
  variable dir ""
  variable order 0
  variable t0 0
  variable open_label ""
  variable open_start 0
  variable open_rss -1
  variable rows {}
  variable synth_labels {begin coarse fine check}
}

proc tel::now_us {} {
  return [clock microseconds]
}

# proc linux, `ps` fork on macOS.
proc tel::mem {} {
  if { [file readable /proc/self/status] } {
    set rss -1
    set hwm -1
    set f [open /proc/self/status r]
    set data [read $f]
    close $f
    regexp -line {^VmRSS:\s+(\d+)} $data -> rss
    regexp -line {^VmHWM:\s+(\d+)} $data -> hwm
    return [list $rss $hwm]
  }
  if { [catch { exec ps -o rss= -p [pid] } out] } {
    return {-1 -1}
  }
  return [list [string trim $out] -1]
}

proc tel::init { } {
  variable on
  variable stat
  variable split_ok
  variable dir
  variable t0
  variable synth_labels

  if { ![env_var_equals SYNTH_TELEMETRY 1] } {
    return
  }
  set on 1
  set stat [env_var_equals SYNTH_TELEMETRY_STAT 1]
  set dir [file join $::env(REPORTS_DIR) telemetry synth]
  file delete -force $dir
  file mkdir $dir
  if { $stat } {
    file mkdir [file join $dir stat]
  }

  # Only split synth on labels this Yosys build actually has. to debug time synth unsplit.
  if { ![catch { ::tee -q -s result.string help synth } h] } {
    set split_ok 1
    foreach l $synth_labels {
      if { ![regexp -line "^\\s+${l}:\\s*\$" $h] } {
        set split_ok 0
      }
    }
  }

  set ver unknown
  if { [env_var_exists_and_non_empty YOSYS_EXE] } {
    catch { set ver [string trim [exec $::env(YOSYS_EXE) -V]] }
  }
  set host unknown
  catch { set host [exec uname -srm] }

  set m [open [file join $dir meta.tsv] w]
  foreach {k v} [list \
      design [env_var_or_empty DESIGN_NAME] \
      platform [env_var_or_empty PLATFORM] \
      flow_variant [env_var_or_empty FLOW_VARIANT] \
      timestamp_epoch [clock seconds] \
      host $host \
      pid [pid] \
      yosys $ver \
      synth_split $split_ok \
      stat_snapshots $stat] {
    puts $m "$k\t$v"
  }
  foreach v {SYNTH_HDL_FRONTEND SYNTH_HIERARCHICAL SYNTH_MINIMUM_KEEP_SIZE
             ABC_AREA SYNTH_ARGS SYNTH_OPERATIONS_ARGS SYNTH_CHECKPOINT} {
    puts $m "$v\t[env_var_or_empty $v]"
  }
  close $m

  set f [open [file join $dir yosys.pid] w]
  puts $f [pid]
  close $f

  set f [open [file join $dir steps.tsv] w]
  puts $f "order\tlabel\tstart_ms\tdur_ms\trss_before_kb\trss_after_kb\thwm_after_kb"
  close $f

  if { !$split_ok } {
    puts "synth telemetry: couldn't confirm synth labels, timing synth calls unsplit"
  }
  puts "synth telemetry: ON -> $dir"
  set t0 [now_us]
}

proc tel::open_step { label } {
  variable dir
  variable open_label
  variable open_start
  variable open_rss

  set open_label $label
  set f [open [file join $dir current_step] w]
  puts $f $label
  close $f
  ::yosys log "@@TEL_BEGIN@@ $label"
  # Sample memory before starting the clock so the sampling cost out.
  set open_rss [lindex [mem] 0]
  set open_start [now_us]
}

proc tel::close_step { } {
  variable on
  variable stat
  variable dir
  variable order
  variable t0
  variable rows
  variable open_label
  variable open_start
  variable open_rss

  if { !$on || $open_label eq "" } {
    return
  }
  set end [now_us]
  lassign [mem] rss hwm
  incr order
  set dur_ms [format %.1f [expr { ($end - $open_start) / 1000.0 }]]
  set start_ms [format %.1f [expr { ($open_start - $t0) / 1000.0 }]]
  set row [list $order $open_label $start_ms $dur_ms $open_rss $rss $hwm]
  lappend rows $row

  set f [open [file join $dir steps.tsv] a]
  puts $f [join $row \t]
  close $f
  ::yosys log "@@TEL_END@@ $open_label $dur_ms ms"

  if { $stat } {
    set out [file join $dir stat [format %03d_%s.json $order $open_label]]
    ::tee -q -o $out stat -json
  }
  set open_label ""
}

# Close the open step (if any) and start a new one.
proc tel::mark { label } {
  variable on
  if { !$on } {
    return
  }
  close_step
  open_step $label
}

# Off: identical call. On: same args, run one label range at a time.
proc tel::synth { args } {
  variable on
  variable split_ok
  variable synth_labels

  if { !$on } {
    return [::synth {*}$args]
  }
  close_step

  if { !$split_ok } {
    open_step synth
    ::synth {*}$args
    close_step
    return
  }

  set i [lsearch -exact $args -run]
  if { $i < 0 } {
    set rest $args
    set from ""
    set to ""
  } else {
    set range [lindex $args [expr { $i + 1 }]]
    set rest [lreplace $args $i [expr { $i + 1 }]]
    set parts [split $range :]
    set from [lindex $parts 0]
    set to [expr { [llength $parts] > 1 ? [lindex $parts 1] : "" }]
  }

  set n [llength $synth_labels]
  set a [expr { $from eq "" ? 0 : [lsearch -exact $synth_labels $from] }]
  set b [expr { $to eq "" ? $n : [lsearch -exact $synth_labels $to] }]

  if { $a < 0 || $b < 0 || $a >= $b } {
    puts "synth telemetry: unexpected synth range '$from:$to', timing it unsplit"
    open_step synth
    ::synth {*}$args
    close_step
    return
  }

  for { set k $a } { $k < $b } { incr k } {
    set lo [lindex $synth_labels $k]
    set hi [expr { $k + 1 < $n ? [lindex $synth_labels [expr { $k + 1 }]] : "" }]
    open_step "synth.$lo"
    ::synth {*}$rest -run "$lo:$hi"
    close_step
  }
}

proc tel::finish { } {
  variable on
  variable dir
  variable t0
  variable rows

  if { !$on } {
    return
  }
  close_step
  set total [expr { ([now_us] - $t0) / 1000.0 }]
  set timed 0.0
  foreach r $rows {
    set timed [expr { $timed + [lindex $r 3] }]
  }
  file delete -force [file join $dir current_step]

  set f [open [file join $dir meta.tsv] a]
  puts $f "total_ms\t[format %.1f $total]"
  close $f

  # Untimed = stat snapshots + sampling overhead + anything between hooks.
  puts [format "synth telemetry: %d steps, total %.1f ms, untimed %.1f ms" \
    [llength $rows] $total [expr { $total - $timed }]]
  puts [format "  %-24s %10s %7s %10s %10s" step dur_ms pct rss_kb hwm_kb]
  foreach r [lrange [lsort -real -decreasing -index 3 $rows] 0 11] {
    lassign $r ord label start dur rss_before rss_after hwm
    set pct [expr { $total > 0 ? 100.0 * $dur / $total : 0 }]
    puts [format "  %-24s %10.1f %6.1f%% %10s %10s" "$ord.$label" $dur $pct $rss_after $hwm]
  }
}
