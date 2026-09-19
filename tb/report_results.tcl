#!/bin/sh
# Hai dong duoi day la sh; Tcl coi ca khoi la MOT chu thich vi dong dau ket thuc \
# bang dau cheo nguoc. bpu_env.sh nap Xcelium (neu chua co) va dat BPU_TCLSH. \
. "$(dirname "$0")/bpu_env.sh" ; exec "$BPU_TCLSH" "$0" ${1+"$@"}
#==============================================================================
# report_results.tcl  --  In BANG KET QUA PASS/FAIL cua ca bo regression.
#
# CACH DUNG
#   cd tb
#   ./report_results.tcl                     ;# tu chon nguon du lieu (xem duoi)
#   ./report_results.tcl xrun_results.txt    ;# chi dinh tep ket qua
#   ./report_results.tcl run_all_results.txt ;# bang cua luot chay QuestaSim
#
#   BPU_COMPARE=run_all_results.txt ./report_results.tcl
#       -> them mot cot doi chieu, liet ke test lech giua hai cong cu.
#
# NGUON DU LIEU (khi khong truyen doi so)
#   1. xrun_results.txt    -- do run_all_xrun.tcl ghi
#   2. run_all_results.txt -- do run_all.do (QuestaSim) ghi
#   3. neu khong co ca hai: tu quet xrun_logs/ hoac questa_logs/ va doc phan
#      tong ket UVM cua tung log.
#
# VI SAO CHI LA VO BOC MONG
#   Toan bo phan in bang nam trong report_results.do de luong QuestaSim
#   (vsim -c -do report_results.do) va luong Xcelium dung chung mot ban ma.
#   Tep nay chi chon nguon du lieu mac dinh roi goi lai.
#==============================================================================

cd [file dirname [file normalize [info script]]]

#--------------------------------------------------- chon nguon du lieu mac dinh --
# Chi dat khi nguoi dung chua dat: bien moi truong cua ho luon duoc uu tien.
if {[llength $argv] >= 1} {
    # Bao loi thay vi im lang roi tu quet log: nguoi dung da chi ro tep nao.
    if {![file exists [lindex $argv 0]]} {
        puts "ERROR: khong thay tep ket qua [lindex $argv 0]."
        exit 2
    }
    set ::env(BPU_RESULTS) [lindex $argv 0]
} elseif {![info exists ::env(BPU_RESULTS)]} {
    foreach f {xrun_results.txt run_all_results.txt} {
        if {[file exists $f]} { set ::env(BPU_RESULTS) $f ; break }
    }
}

if {![info exists ::env(BPU_LOGDIR)]} {
    foreach d {xrun_logs questa_logs} {
        if {[file isdirectory $d]} { set ::env(BPU_LOGDIR) $d ; break }
    }
}

source report_results.do
