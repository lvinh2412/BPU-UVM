#!/bin/sh
# Hai dong duoi day la sh; Tcl coi ca khoi la MOT chu thich vi dong dau ket thuc \
# bang dau cheo nguoc. bpu_env.sh nap Xcelium (neu chua co) va dat BPU_TCLSH. \
. "$(dirname "$0")/bpu_env.sh" ; exec "$BPU_TCLSH" "$0" ${1+"$@"}
#==============================================================================
# run_all_xrun.tcl  --  Chay TOAN BO test trong testlist_44.txt bang Xcelium.
#
# CACH DUNG
#   cd tb
#   ./run_all_xrun.tcl                       ;# MAC DINH: 44 muc cua testplan
#   ./run_all_xrun.tcl my_list.txt           ;# danh sach khac
#   BPU_ONLY='carry_*' ./run_all_xrun.tcl      ;# loc theo mau ten test
#   BPU_COV=1 ./run_all_xrun.tcl             ;# kem coverage (cham hon)
#
# DANH SACH TEST
#   testlist_44.txt  44 muc chuc nang cua sheet TestCase trong testplan (mac dinh)
#
#   Neu he thong co tclsh:  tclsh run_all_xrun.tcl
#
# TUY CHON (bien moi truong)
#   BPU_TESTLIST=<tep>          danh sach test (doi so vi tri uu tien hon)
#   BPU_LOGDIR=xrun_logs        thu muc log tung test
#   BPU_RESULTS=xrun_results.txt tep ket qua cho report_results.tcl doc
#   BPU_VERBOSITY=UVM_LOW       muc verbosity UVM
#   BPU_ONLY=<glob>             chi chay test khop mau (vd 'btb_*')
#   BPU_SEED=<n>                co dinh seed (mac dinh de xrun tu chon)
#   BPU_COV=1                   bat coverage, luu vao cov_work/scope/<test>
#   BPU_NOBUILD=1               bo qua buoc elaborate
#   BPU_TCLSH=<path>            chi dinh trinh thong dich Tcl
#
# KET QUA
#   xrun_logs/sim_<test>.log    transcript day du cua tung test
#   xrun_results.txt            mot dong moi test -- xem bang bang:
#                               ./report_results.tcl
#
# VI SAO DUNG "xrun -R" CHU KHONG PHAI "xrun -f run.f" MOI TEST
#   -R chay lai dung snapshot da elaborate trong xcelium.d, bo qua toan bo khau
#   kiem tra phu thuoc va nap thu vien. Do o day: 3.7s/test so voi ~15s. Doi lai
#   phai elaborate mot lan truoc (script tu lam, xem proc bpu_elaborate).
#   Che do coverage KHONG dung -R vi snapshot mac dinh khong co instrument, nen
#   ro lai ve "xrun -f run.f -coverage all" giong muc covrun trong Makefile.
#
# PHAN XU PASS/FAIL
#   Lay tu phan tong ket cuoi cua uvm_report_server (UVM_ERROR/UVM_FATAL), khong
#   dem tung dong loi -- mot so test co in thong bao loi de minh hoa. Ma thoat
#   cua xrun chi dung khi log KHONG co phan tong ket (treo hoac loi nap).
#==============================================================================

cd [file dirname [file normalize [info script]]]
source bpu_tcl_lib.tcl

#------------------------------------------------------------------ tham so --
proc bpu_env {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}

# Mac dinh la 44 muc chuc nang cua testplan; truyen tep khac de chay danh sach
# rieng: ./run_all_xrun.tcl my_list.txt
set testlist [bpu_env BPU_TESTLIST "testlist_44.txt"]
if {[llength $argv] >= 1} { set testlist [lindex $argv 0] }

set logdir    [bpu_env BPU_LOGDIR    "xrun_logs"]
set resfile   [bpu_env BPU_RESULTS   "xrun_results.txt"]
set verbosity [bpu_env BPU_VERBOSITY "UVM_LOW"]
set only      [bpu_env BPU_ONLY      ""]
set seed      [bpu_env BPU_SEED      ""]
set do_cov    [bpu_env BPU_COV       0]
set nobuild   [bpu_env BPU_NOBUILD   0]

if {![file exists $testlist]} {
    puts "ERROR: khong thay $testlist. Chay o thu muc tb/."
    exit 2
}

# bpu_env.sh da thu nap Xcelium roi; toi day van thieu thi bao cho ro, vi thong
# bao mac dinh cua exec ("couldn't execute") khong goi y duoc gi.
if {![llength [auto_execok xrun]]} {
    puts "ERROR: khong thay xrun trong PATH."
    puts "  Nap moi truong Xcelium roi chay lai:"
    puts "    source /home/abc24/eda/cadence/xcelium/XCELIUM1803.sh"
    puts "  Neu Xcelium cai o cho khac, sua duong dan mac dinh trong bpu_env.sh"
    puts "  hoac dat: BPU_XCELIUM_SETUP=<duong dan script khoi tao>"
    exit 2
}

file mkdir $logdir

#-------------------------------------------------------------- doc testlist --
set tests {}
set fh [open $testlist r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    if {$only ne "" && ![string match $only $line]} { continue }
    lappend tests $line
}
close $fh

if {![llength $tests]} {
    puts "ERROR: khong co test nao trong $testlist[expr {$only eq "" ? "" : " khop mau '$only'"}]."
    exit 2
}

#------------------------------------------------------------------------------
# bpu_run_xrun <danh_sach_doi_so> <log>
#   Chay xrun, don het stdout+stderr vao <log>, tra ve ma thoat.
#   exec bao loi ca khi tien trinh con ghi ra stderr, nen phai lay ma thoat that
#   tu ::errorCode ({CHILDSTATUS <pid> <code>}) thay vi tin vao gia tri catch.
#------------------------------------------------------------------------------
proc bpu_run_xrun {args_list log} {
    set cmd [linsert $args_list 0 xrun]
    set rc 0
    if {[catch {eval exec $cmd [list >& $log]}]} {
        if {[lindex $::errorCode 0] eq "CHILDSTATUS"} {
            set rc [lindex $::errorCode 2]
        } else {
            set rc 1
        }
    }
    return $rc
}

#------------------------------------------------------------------------------
# bpu_elaborate
#   Elaborate mot lan de cac test sau dung lai snapshot. xrun tu bo qua neu
#   xcelium.d con moi (do o day: 0.2s), nen goi vo dieu kien la an toan.
#------------------------------------------------------------------------------
proc bpu_elaborate {do_cov} {
    set opts [list -f run.f -elaborate]
    if {$do_cov} { lappend opts -coverage all }
    return [bpu_run_xrun $opts "build_xrun.log"]
}

#--------------------------------------------------------------------- chay --
set total [llength $tests]
puts "=========================================================================="
puts " BPU regression (Xcelium) -- $total test, log=$logdir/"
puts [format " che do: %s%s" \
        [expr {$do_cov ? "xrun -f run.f -coverage all" : "xrun -R (snapshot)"}] \
        [expr {$seed eq "" ? "" : ", seed=$seed"}]]
puts "=========================================================================="
flush stdout

if {!$nobuild} {
    puts -nonewline " elaborate ... " ; flush stdout
    set t0 [clock seconds]
    set rc [bpu_elaborate $do_cov]
    if {$rc != 0} {
        puts "THAT BAI (rc=$rc). Xem build_xrun.log"
        exit 2
    }
    puts "xong ([expr {[clock seconds] - $t0}]s)"
    flush stdout
}

set results {}
set n_pass 0
set n_fail 0
set idx 0
set t_start [clock seconds]

foreach t $tests {
    incr idx
    set log [file join $logdir "sim_$t.log"]

    if {$do_cov} {
        set opts [list -f run.f -coverage all -covoverwrite -covtest $t]
    } else {
        set opts [list -R]
    }
    if {$seed ne ""} { lappend opts -svseed $seed }
    lappend opts +UVM_TESTNAME=$t +UVM_VERBOSITY=$verbosity

    set t0 [clock seconds]
    set rc [bpu_run_xrun $opts $log]
    set secs [expr {[clock seconds] - $t0}]

    set res [bpu_scan_log $log]
    set nerr [lindex $res 0]
    set nfat [lindex $res 1]
    set nmis [lindex $res 2]

    # Phan tong ket UVM la nguon phan xu. Chi khi khong co no moi xet ma thoat:
    # UVM_FATAL cung in tong ket roi $finish, ma vai luong lai bao ma thoat khac 0.
    if {$nerr eq "?"} {
        set verdict [expr {$rc != 0 ? "FAIL_RC=$rc" : "FAIL_NOSUMMARY"}]
    } else {
        set verdict [bpu_verdict $nerr $nfat]
    }

    if {$verdict eq "PASS"} { incr n_pass } else { incr n_fail }
    lappend results [list $t $verdict $nmis $nerr $nfat $secs]

    puts [format "  \[%3d/%3d\] %-46s %-14s %4ds" $idx $total $t $verdict $secs]
    flush stdout
}

set elapsed [expr {[clock seconds] - $t_start}]

#------------------------------------------------------------------ ghi file --
set out [open $resfile w]
puts $out "# BPU regression results (Xcelium) -- sinh boi run_all_xrun.tcl"
puts $out "# cot: TEST VERDICT MISCMP UVM_ERROR UVM_FATAL SECONDS"
foreach r $results { puts $out [join $r " "] }
puts $out "# TOTAL PASS=$n_pass FAIL=$n_fail ELAPSED=${elapsed}s"
close $out

puts "=========================================================================="
puts [format " XONG: PASS=%d  FAIL=%d  (tong %d) trong %dm%02ds" \
        $n_pass $n_fail $total [expr {$elapsed / 60}] [expr {$elapsed % 60}]]
puts " Ket qua: $resfile   -- xem bang: ./report_results.tcl"
puts "=========================================================================="

if {$n_fail} { exit 1 }
exit 0
