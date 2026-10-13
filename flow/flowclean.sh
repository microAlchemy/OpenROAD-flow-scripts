#!/bin/sh
# flowclean — collapse OpenROAD/Yosys flow logs to signal
# usage: ./flowclean logs/nangate45/gcd/base/*   | less
cat "$@" \
| grep -vE '^(OpenROAD bazel-nostamp|Features included|This program is licensed|Components of this program)' \
| grep -vE '^\[INFO ORD-0030\]|^read_(liberty|db|sdc) |^source .*\.tcl$' \
| grep -vE '^[[:space:]]*"[a-z_]+__.*(fastroute|snapshot_batch)' \
| grep -vE '^\[INFO DRT-00(24|28|33|35|36)\]' \
| grep -vE '^[0-9]+(\.[0-9]+)*\. Executing (OPT_|PROC_|FSM_|MEMORY_|HIERARCHY|AST)' \
| grep -vE '^[0-9]+(\.[0-9]+)*\. (Analyzing|Rerunning|Finished)' \
| grep -vE '^[[:space:]]*[0-9]+[*+]?[[:space:]]*\|' \
| grep -vE 'Completing [0-9]+% with' \
| grep -vE '^Total wire length on LAYER metal([17-9]|10) = 0 um' \
| grep -vE '^[[:space:]]+(active|metal[0-9]+)[[:space:]]+[0-9]+$' \
| grep -vE '^Log +Ext +Elapsed|^ +s +s +Elapsed' \
| grep -vE '^[[:space:]]*$' \
| uniq
