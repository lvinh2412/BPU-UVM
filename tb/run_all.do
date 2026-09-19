#==============================================================================
# run_all.do  --  Chay TOAN BO test trong testlist_44.txt bang MOT phien vsim.
#
# CACH DUNG
#   cd tb
#   make -f Makefile.questa build          ;# phai build truoc
#   vsim -c -do run_all.do
#
#   Tuy chon (dat truoc khi goi, bang -gTESTLIST=... khong dung duoc cho .do,
#   nen dung bien moi truong):
#     BPU_TESTLIST=my_list.txt  vsim -c -do run_all.do
#     BPU_TOP=top_opt_cov       vsim -c -do run_all.do   ;# ban co coverage
#     BPU_COV=1                 vsim -c -do run_all.do   ;# luu UCDB moi test
#
# KET QUA
#   questa_logs/sim_<test>.log   -- transcript day du cua tung test
#   run_all_results.txt          -- mot dong moi test, doc boi report_results.do
#
# VI SAO MOT PHIEN vsim CHU KHONG PHAI MOI TEST MOT TIEN TRINH
#   Nap thu vien va anh xa design chiem phan lon thoi gian khoi dong. Trong mot
#   phien, `vsim` / `quit -sim` chi nap lai snapshot da toi uu nen nhanh hon
#   han. Doi lai phai dat -onfinish stop (xem duoi).
#
# BAY QUAN TRONG -- -onfinish stop
#   UVM ket thuc bang $finish. O che do batch, $finish lam vsim THOAT LUON, nen
#   vong lap se chet ngay sau test dau tien. -onfinish stop tra dieu khien ve
#   cho script thay vi thoat.
#==============================================================================

source bpu_tcl_lib.tcl

# Mac dinh la 44 muc chuc nang cua testplan; dat BPU_TESTLIST de chay danh sach
# rieng: BPU_TESTLIST=my_list.txt vsim -c -do run_all.do
quietly set testlist "testlist_44.txt"
if {[info exists ::env(BPU_TESTLIST)]} { set testlist $::env(BPU_TESTLIST) }

quietly set top "top_opt"
if {[info exists ::env(BPU_TOP)]} { set top $::env(BPU_TOP) }

quietly set do_cov 0
if {[info exists ::env(BPU_COV)]} { set do_cov $::env(BPU_COV) }

quietly set logdir "questa_logs"
if {[info exists ::env(BPU_LOGDIR)]} { set logdir $::env(BPU_LOGDIR) }

quietly set verbosity "UVM_LOW"
if {[info exists ::env(BPU_VERBOSITY)]} { set verbosity $::env(BPU_VERBOSITY) }

quietly set questa_root "/home/abc24/eda/questa/questaSim/questasim"
if {[info exists ::env(QUESTA_ROOT)]} { set questa_root $::env(QUESTA_ROOT) }
quietly set uvm_dpi "$questa_root/uvm-1.2/linux_x86_64/uvm_dpi"

#------------------------------------------------------------------ kiem tra --
if {![file exists $testlist]} {
    echo "ERROR: khong thay $testlist. Dung o thu muc tb/ va build truoc."
    quit -code 2
}
file mkdir $logdir

#-------------------------------------------------------------- doc testlist --
quietly set tests {}
quietly set fh [open $testlist r]
while {[gets $fh line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string index $line 0] eq "#"} { continue }
    lappend tests $line
}
close $fh

quietly set total [llength $tests]
echo "=========================================================================="
echo " BPU regression -- $total test, top=$top, log=$logdir/"
echo "=========================================================================="

#--------------------------------------------------------------------- chay --
quietly set results {}
quietly set n_pass 0
quietly set n_fail 0
quietly set idx 0

foreach t $tests {
    incr idx
    set log "$logdir/sim_$t.log"

    # Moi test mot transcript rieng. Lenh nay dong transcript truoc do lai.
    transcript file $log

    # Nap design. -onfinish stop: xem ghi chu o dau tep.
    if {$do_cov} {
        set rc [catch {
            vsim -quiet -onfinish stop -coverage \
                 -sv_lib $uvm_dpi -suppress 3947 \
                 +UVM_TESTNAME=$t +UVM_VERBOSITY=$verbosity $top
        } emsg]
    } else {
        set rc [catch {
            vsim -quiet -onfinish stop \
                 -sv_lib $uvm_dpi -suppress 3947 \
                 +UVM_TESTNAME=$t +UVM_VERBOSITY=$verbosity $top
        } emsg]
    }

    if {$rc} {
        set verdict "FAIL_LOAD"
        set nerr "?" ; set nfat "?" ; set nmis 0
    } else {
        catch {run -all}
        if {$do_cov} { catch {coverage save "cov_$t.ucdb"} }
        catch {quit -sim}

        # Transcript phai duoc day xuong dia truoc khi doc lai.
        transcript file ""
        set res [bpu_scan_log $log]
        set nerr [lindex $res 0]
        set nfat [lindex $res 1]
        set nmis [lindex $res 2]

        # UVM summary la nguon phan xu; chi khi khong co summary moi coi la
        # loi nap/treo.
        if {$nerr eq "?"} {
            set verdict "FAIL_NOSUMMARY"
        } elseif {$nerr != 0 || $nfat != 0} {
            set verdict "FAIL"
        } else {
            set verdict "PASS"
        }
    }

    if {$verdict eq "PASS"} { incr n_pass } else { incr n_fail }
    lappend results [list $t $verdict $nmis $nerr $nfat]

    # In tien do ra man hinh (transcript dang tro ve mac dinh nen echo hien ra).
    echo [format "  \[%3d/%3d\] %-46s %s" $idx $total $t $verdict]
}

#------------------------------------------------------------------ ghi file --
quietly set out [open "run_all_results.txt" w]
puts $out "# BPU regression results -- sinh boi run_all.do"
puts $out "# cot: TEST VERDICT MISCMP UVM_ERROR UVM_FATAL"
foreach r $results { puts $out [join $r " "] }
puts $out "# TOTAL PASS=$n_pass FAIL=$n_fail"
close $out

echo "=========================================================================="
echo " XONG: PASS=$n_pass  FAIL=$n_fail  (tong $total)"
echo " Ket qua: run_all_results.txt   -- xem bang: vsim -c -do report_results.do"
echo "=========================================================================="

quit -f
