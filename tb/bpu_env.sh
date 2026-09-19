#==============================================================================
# bpu_env.sh  --  Chuan bi moi truong cho run_all_xrun.tcl va report_results.tcl
#
# Tep nay duoc SOURCE (khong phai chay) boi phan dau /bin/sh cua hai script do.
# Viec cua no: bao dam co xrun trong PATH, roi tim mot trinh thong dich Tcl va
# dat ra bien BPU_TCLSH.
#
# TUY CHON
#   BPU_XCELIUM_SETUP=<duong dan>  script khoi tao Xcelium can source
#   BPU_TCLSH=<duong dan tclsh>    chi dinh thang trinh thong dich Tcl
#
# VI SAO PHAI TU SOURCE XCELIUM
#   xrun khong nam san trong PATH khi mo terminal moi -- phai source
#   XCELIUM1803.sh (giong muc "make src"). Script do con dat CDS_LIC_FILE va
#   UVMHOME, ma run.f dung UVMHOME o dong "-uvmhome $UVMHOME", nen thieu no thi
#   khau elaborate hong chu khong chi la "khong tim thay lenh".
#
# VI SAO CAN TCLSH RIENG
#   May nay khong cai tclsh he thong. Xcelium co dong goi mot ban 8.4 trong
#   tools.lnx86/tcltk-*, nhung ban do can LD_LIBRARY_PATH tro toi libtcl8.4.so
#   thi moi nap duoc.
#==============================================================================

BPU_XCELIUM_SETUP=${BPU_XCELIUM_SETUP:-/home/abc24/eda/cadence/xcelium/XCELIUM1803.sh}

if ! command -v xrun >/dev/null 2>&1; then
    if [ -r "$BPU_XCELIUM_SETUP" ]; then
        . "$BPU_XCELIUM_SETUP"
    fi
fi

if [ -z "${BPU_TCLSH:-}" ]; then
    if command -v tclsh >/dev/null 2>&1; then
        BPU_TCLSH=tclsh
    else
        # Suy ra thu muc cai dat tu vi tri xrun (.../tools/bin/xrun), du phong
        # bang XCELIUM_HOME do script khoi tao dat ra.
        _bpu_xb=$(command -v xrun 2>/dev/null)
        if [ -n "$_bpu_xb" ]; then
            _bpu_root=$(dirname "$(dirname "$(dirname "$_bpu_xb")")")
        else
            _bpu_root=${XCELIUM_HOME:-}
        fi
        for _bpu_d in "$_bpu_root"/tools.lnx86/tcltk-*; do
            if [ -x "$_bpu_d/bin/64bit/tclsh8.4" ]; then
                BPU_TCLSH="$_bpu_d/bin/64bit/tclsh8.4"
                LD_LIBRARY_PATH="$_bpu_d/lib/64bit:${LD_LIBRARY_PATH:-}"
                export LD_LIBRARY_PATH
                break
            fi
        done
        unset _bpu_xb _bpu_root _bpu_d
    fi
fi

if [ -z "${BPU_TCLSH:-}" ]; then
    echo "ERROR: khong tim duoc trinh thong dich Tcl." >&2
    echo "  Da thu: tclsh trong PATH, roi ban dong goi theo Xcelium." >&2
    echo "  Cach xu ly:" >&2
    echo "    source $BPU_XCELIUM_SETUP" >&2
    echo "  hoac chi dinh thang:" >&2
    echo "    BPU_TCLSH=/duong/dan/toi/tclsh $0" >&2
    exit 2
fi

export BPU_TCLSH
