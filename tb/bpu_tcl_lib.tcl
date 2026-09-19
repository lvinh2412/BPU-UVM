#==============================================================================
# bpu_tcl_lib.tcl  --  ham dung chung cho run_all.do, run_all_xrun.tcl va
#                      report_results.do / report_results.tcl
#
# Thuan TCL, khong dung lenh rieng cua vsim, nen chay duoc ca duoi
#   vsim -c -do ...      (QuestaSim)
#   tclsh ...            (khong can trinh mo phong)
#==============================================================================

#------------------------------------------------------------------------------
# quietly -- co san trong vsim (chan viec in gia tri tra ve). Duoi tclsh thi
# khong co, nen dinh nghia mot ban thay the de cung mot script chay duoc ca hai.
#------------------------------------------------------------------------------
if {![llength [info commands quietly]]} {
    proc quietly {args} { uplevel 1 $args }
}

#------------------------------------------------------------------------------
# lassign -- lenh cua Tcl 8.5. Trinh thong dich di kem Xcelium 18.03 la 8.4.20
# nen phai tu dung lai: gan tung phan tu cua <values> cho tung bien trong <args>,
# bien thua thi nhan chuoi rong, tra ve phan du cua danh sach.
#------------------------------------------------------------------------------
if {![llength [info commands lassign]]} {
    proc lassign {values args} {
        while {[llength $args] > [llength $values]} { lappend values {} }
        uplevel 1 [list foreach $args $values break]
        return [lrange $values [llength $args] end]
    }
}

#------------------------------------------------------------------------------
# bpu_scan_log <duong_dan_log>
#
#   Doc mot transcript va tra ve  {UVM_ERROR UVM_FATAL MISCMP}.
#   Tra "?" cho UVM_ERROR/UVM_FATAL neu log KHONG co phan tong ket cua UVM
#   (test treo, hoac nap design that bai).
#
#   VI SAO LAY TU PHAN TONG KET chu khong dem tung dong:
#     mot so test in ra thong bao loi "co chu y" de minh hoa; dem tung dong se
#     tinh nham. Phan tong ket cuoi cua uvm_report_server moi la con so phan xu.
#     Lay dong CUOI CUNG khop, vi UVM co the in tong ket nhieu lan.
#
#   Questa them tien to "# " vao moi dong transcript, Xcelium thi khong --
#   bieu thuc duoi day chap nhan ca hai.
#------------------------------------------------------------------------------
proc bpu_scan_log {path} {
    set nerr "?"
    set nfat "?"
    set nmis 0
    if {![file exists $path]} { return [list $nerr $nfat $nmis] }

    set fh [open $path r]
    while {[gets $fh line] >= 0} {
        if {[regexp {^\#?\s*UVM_ERROR\s*:\s*(\d+)} $line -> v]} { set nerr $v }
        if {[regexp {^\#?\s*UVM_FATAL\s*:\s*(\d+)} $line -> v]} { set nfat $v }
        if {[string first "MISCMP" $line] >= 0} { incr nmis }
    }
    close $fh
    return [list $nerr $nfat $nmis]
}

#------------------------------------------------------------------------------
# bpu_verdict <nerr> <nfat>
#   Quy tac phan xu dung chung: phan tong ket UVM la nguon quyet dinh.
#------------------------------------------------------------------------------
proc bpu_verdict {nerr nfat} {
    if {$nerr eq "?"} { return "FAIL_NOSUMMARY" }
    if {$nerr != 0 || $nfat != 0} { return "FAIL" }
    return "PASS"
}

#------------------------------------------------------------------------------
# bpu_read_results <duong_dan>
#   Doc run_all_results.txt -> danh sach {test verdict miscmp nerr nfat}
#------------------------------------------------------------------------------
proc bpu_read_results {path} {
    set out {}
    if {![file exists $path]} { return $out }
    set fh [open $path r]
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} { continue }
        lappend out $line
    }
    close $fh
    return $out
}

#------------------------------------------------------------------------------
# bpu_group <ten_test>
#   Xep test vao nhom de bang bao cao gom lai cho de doc.
#------------------------------------------------------------------------------
proc bpu_group {t} {
    if {[string match "pattern_*" $t]}         { return "Mau nhanh (15.x)" }
    if {[string match "stress_*" $t] ||
        [string match "random_pipeline*" $t]}  { return "Stress / random (16.x)" }
    return "Chuc nang (1.x - 14.x)"
}

#------------------------------------------------------------------------------
# bpu_puts <chuoi>
#   echo duoi vsim, puts duoi tclsh.
#------------------------------------------------------------------------------
proc bpu_puts {s} {
    if {[llength [info commands echo]]} { echo $s } else { puts $s }
}
