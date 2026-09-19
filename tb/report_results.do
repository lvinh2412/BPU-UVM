#==============================================================================
# report_results.do  --  In BANG KET QUA PASS/FAIL cua ca bo regression.
#
# CACH DUNG
#   vsim -c -do report_results.do          ;# duoi QuestaSim
#   tclsh report_results.do                ;# khong can trinh mo phong
#
#   Bien moi truong tuy chon:
#     BPU_RESULTS=run_all_results.txt   -- tep ket qua do run_all.do sinh ra
#     BPU_LOGDIR=questa_logs            -- neu khong co tep ket qua, quet log
#     BPU_COMPARE=ket_qua_xrun.txt  -- them mot cot doi chieu cong cu khac
#
# NGUON DU LIEU
#   Uu tien run_all_results.txt (do run_all.do ghi). Neu khong co, script tu
#   quet thu muc log va doc phan tong ket UVM cua tung tep -- nen van dung duoc
#   voi log sinh boi bat ky luong nao, ke ca xrun.
#==============================================================================

source bpu_tcl_lib.tcl

quietly set results_file "run_all_results.txt"
if {[info exists ::env(BPU_RESULTS)]} { quietly set results_file $::env(BPU_RESULTS) }

quietly set logdir "questa_logs"
if {[info exists ::env(BPU_LOGDIR)]} { quietly set logdir $::env(BPU_LOGDIR) }

quietly set compare_file ""
if {[info exists ::env(BPU_COMPARE)]} { quietly set compare_file $::env(BPU_COMPARE) }

#------------------------------------------------------------------------------
# Toan bo phan than nam trong mot proc: duoi vsim, moi lenh o cap cao nhat deu
# in gia tri tra ve ra man hinh, lam ban bao cao. Trong proc thi khong.
#------------------------------------------------------------------------------
proc bpu_report {results_file logdir compare_file} {
#-------------------------------------------------------------- thu thap so --
    set rows {}
    if {[file exists $results_file]} {
        set src "$results_file"
        foreach line [bpu_read_results $results_file] { lappend rows $line }
    } else {
        # Du phong: quet log. Dung duoc cho ca xrun (LOGDIR=xrun_logs).
        set src "quet $logdir/sim_*.log"
        foreach f [lsort [glob -nocomplain [file join $logdir "sim_*.log"]]] {
            set t [file rootname [file tail $f]]
            set t [string range $t 4 end]            ;# bo tien to "sim_"
            set r [bpu_scan_log $f]
            lassign $r nerr nfat nmis
            lappend rows [list $t [bpu_verdict $nerr $nfat] $nmis $nerr $nfat]
        }
    }

    if {![llength $rows]} {
        bpu_puts "ERROR: khong co du lieu. Chay run_all.do (hoac run_all_xrun.tcl) truoc,"
        bpu_puts "       hoac dat BPU_LOGDIR tro toi thu muc log."
        if {[llength [info commands quit]]} { quit -code 2 } else { exit 2 }
    }

    # Cot thu 6 (thoi gian chay) chi co trong ket qua cua run_all_xrun.tcl.
    # Duong quet log du phong khong co, nen chi in cot nay khi that su co du lieu.
    set have_time 0
    foreach r $rows { if {[llength $r] >= 6} { set have_time 1 ; break } }

    #------------------------------------------- cot doi chieu (tuy chon) --------
    array set cmp {}
    set have_cmp 0
    if {$compare_file ne "" && [file exists $compare_file]} {
        set have_cmp 1
        set fh [open $compare_file r]
        while {[gets $fh line] >= 0} {
            set p [split [string trim $line]]
            set p [lsearch -all -inline -not -exact $p ""]
            if {[llength $p] >= 2 && [lindex $p 0] ne "TEST" &&
                ![string match "=*" [lindex $p 0]] &&
                ![string match "-*" [lindex $p 0]]} {
                set cmp([lindex $p 0]) [lindex $p 1]
            }
        }
        close $fh
    }

    #--------------------------------------------------------------- gom nhom ----
    array set bygroup {}
    foreach r $rows { lappend bygroup([bpu_group [lindex $r 0]]) $r }

    #------------------------------------------------------------------- in ra ---
    set W 78
    bpu_puts ""
    bpu_puts [string repeat "=" $W]
    bpu_puts " BANG KET QUA REGRESSION BPU"
    bpu_puts " nguon: $src"
    if {$have_cmp} { bpu_puts " cot doi chieu: $compare_file" }
    bpu_puts [string repeat "=" $W]

    set n_pass 0
    set n_fail 0
    set fails {}
    set diffs {}

    foreach g [lsort [array names bygroup]] {
        set gp 0 ; set gf 0
        bpu_puts ""
        bpu_puts "-- $g [string repeat "-" [expr {$W - [string length $g] - 4}]]"
        set head "MISCMP  ERR/FAT"
        if {$have_time} { append head "   TIME" }
        if {$have_cmp} {
            bpu_puts [format "   %-44s %-9s %-9s %s" "TEST" "KET QUA" "DOI CHIEU" $head]
        } else {
            bpu_puts [format "   %-44s %-9s %s" "TEST" "KET QUA" $head]
        }
        foreach r [lsort -index 0 $bygroup($g)] {
            set secs ""
            lassign $r t v nmis nerr nfat secs
            if {$v eq "PASS"} { incr n_pass ; incr gp } else { incr n_fail ; incr gf ; lappend fails $r }
            if {$have_time} {
                set tail [format "%6s  %-7s %5s" $nmis "$nerr/$nfat" \
                                 [expr {$secs eq "" ? "-" : "${secs}s"}]]
            } else {
                set tail [format "%6s  %s/%s" $nmis $nerr $nfat]
            }
            if {$have_cmp} {
                set o "-"
                if {[info exists cmp($t)]} { set o $cmp($t) }
                if {$o ne "-" && $o ne $v} { lappend diffs [list $t $v $o] ; set o "$o  <<" }
                bpu_puts [format "   %-44s %-9s %-9s %s" $t $v $o $tail]
            } else {
                bpu_puts [format "   %-44s %-9s %s" $t $v $tail]
            }
        }
        bpu_puts [format "   %-44s %d PASS / %d FAIL" "  -> nhom nay:" $gp $gf]
    }

    bpu_puts ""
    bpu_puts [string repeat "=" $W]
    bpu_puts [format " TONG: %d test   %d PASS   %d FAIL" [expr {$n_pass + $n_fail}] $n_pass $n_fail]
    bpu_puts [string repeat "=" $W]

    if {[llength $fails]} {
        bpu_puts ""
        bpu_puts " TEST FAIL:"
        foreach r $fails {
            lassign $r t v nmis nerr nfat
            bpu_puts [format "   %-46s %-14s UVM_ERROR=%s UVM_FATAL=%s" $t $v $nerr $nfat]
        }
    } else {
        bpu_puts ""
        bpu_puts " Khong co test nao FAIL."
    }

    if {$have_cmp && [llength $diffs]} {
        bpu_puts ""
        bpu_puts " LECH GIUA HAI CONG CU:"
        foreach d $diffs {
            bpu_puts [format "   %-46s nay=%-6s doi chieu=%s" [lindex $d 0] [lindex $d 1] [lindex $d 2]]
        }
    } elseif {$have_cmp} {
        bpu_puts ""
        bpu_puts " Hai cong cu khop nhau o moi test."
    }
    bpu_puts ""
}

bpu_report $results_file $logdir $compare_file
if {[llength [info commands quit]]} { quit -f }
