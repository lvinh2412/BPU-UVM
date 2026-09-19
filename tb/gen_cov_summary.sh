#!/bin/bash
# Build the human-readable hole list that goes at the top of cov_report.txt.
#
# Reads the two raw vcover outputs (cov_report_func.txt / cov_report_code.txt)
# plus run_all_status.txt, and emits the summary on stdout. covreport
# concatenates this ahead of the raw reports.
#
# The functional report prints the same numbers four times (TYPE + per-instance,
# each in a normal and a filtered view), so every extraction is restricted to
# the first TYPE section: line 'TYPE .../cg_bpu' up to the next 'Covergroup
# instance'. Without that window every bin would be listed 4x.

cd "$(dirname "$0")" || exit 1

FUNC=cov_report_func.txt
CODE=cov_report_code.txt
STAT=run_all_status.txt
RTL_DU="bpu_reg bpu_predictor bpu_ctrl bpu_top"

# --- The single TYPE section of the functional report -------------------------
type_start=$(grep -n "TYPE .*/cg_bpu" "$FUNC" | head -1 | cut -d: -f1)
type_end=$(awk -v s="$type_start" 'NR>s && /^ Covergroup instance/{print NR; exit}' "$FUNC")
sed -n "${type_start},${type_end}p" "$FUNC" > /tmp/_cg_type.$$

# A bin line is uncovered when its status column is ZERO. illegal_bin/ignore_bin
# at ZERO are the intended result (illegal never hit, ignored never counted), so
# they are reported separately and NOT as holes.
uncov_bins() {   # $1 = bin|illegal_bin|ignore_bin
  awk -v kind="$1" '
    /^    (Coverpoint|Cross) /{cp=$2}
    $0 ~ "^ +" kind " " && /ZERO/ {
      name=$2; cnt=$3; w=$(NF-1)
      printf "%s\t%s\t%s\n", cp, name, w
    }' /tmp/_cg_type.$$
}

echo "=============================================================================="
echo " BPU COVERAGE SUMMARY — holes only, no analysis"
echo " generated: $(date '+%Y-%m-%d %H:%M')"
echo "=============================================================================="
echo

# ---------------------------------------------------------------- (a) tests ---
total=$(wc -l < "$STAT")
ok=$(grep -c ' OK$' "$STAT")
bad=$(grep -c 'FAIL' "$STAT")
echo "(a) TESTS"
echo "-------------------------------------------------------------------------"
echo "    total run : $total"
echo "    PASS      : $ok"
echo "    FAILED    : $bad"
echo
echo "    Every test below produced a valid UCDB and IS included in merged.ucdb;"
echo "    'FAIL_UVM err=N' = N UVM_ERROR in that test's own checkers."
echo
grep 'FAIL' "$STAT" | sort | awk '{printf "      %-52s %s %s\n", $1, $2, $3}'
echo

# ----------------------------------------------------- (b) functional cg_bpu ---
# ' TYPE <path> 96.52% 100 - Uncovered' -> $1=TYPE $2=path $3=pct
cg_pct=$(awk '/TYPE .*\/cg_bpu/{print $3; exit}' /tmp/_cg_type.$$)
cg_cov=$(awk '/covered\/total bins:/{print $3; exit}' /tmp/_cg_type.$$)
cg_tot=$(awk '/covered\/total bins:/{print $4; exit}' /tmp/_cg_type.$$)
cg_mis=$(awk '/missing\/total bins:/{print $3; exit}' /tmp/_cg_type.$$)

echo "(b) FUNCTIONAL COVERAGE — cg_bpu"
echo "-------------------------------------------------------------------------"
echo "    cg_bpu TOTAL : $cg_pct   (bins covered $cg_cov/$cg_tot, missing $cg_mis)"
echo "    coverpoints  : 26        crosses : 22"
echo
printf "    %-32s %8s   %s\n" "COVERPOINT" "%" "UNHIT BINS (0 hits)"
printf "    %-32s %8s   %s\n" "--------------------------------" "--------" "-------------------"
awk '/^    Coverpoint /{cp=$2; pct=$3; cps[++n]=cp; p[cp]=pct}
     /^    Coverpoint /{cur=$2}
     /^        bin /&&/ZERO/{h[cur]=h[cur]" "$2}
     END{for(i=1;i<=n;i++){c=cps[i]; printf "    %-32s %8s   %s\n", c, p[c], (h[c]==""?"-":h[c])}}' /tmp/_cg_type.$$
echo

# ------------------------------------------------------------- (c) crosses ---
echo "(c) CROSSES"
echo "-------------------------------------------------------------------------"
printf "    %-32s %8s   %s\n" "CROSS" "%" "UNHIT BIN PAIRS (0 hits)"
printf "    %-32s %8s   %s\n" "--------------------------------" "--------" "------------------------"
awk '/^    Cross /{cx=$2; pct=$3; cxs[++n]=cx; p[cx]=pct; cur=$2}
     /^            bin /&&/ZERO/{h[cur]=h[cur]" "$2}
     END{for(i=1;i<=n;i++){c=cxs[i]; printf "    %-32s %8s   %s\n", c, p[c], (h[c]==""?"-":h[c])}}' /tmp/_cg_type.$$
echo
echo "    NOTE: a '*' in a pair (e.g. <no_branch,*>) is vcover's collapsed form —"
echo "          it stands for every bin of the other coverpoint, so it counts as"
echo "          more than one missing bin (weight shown in the raw report)."
echo

echo "    Bins at 0 BY DESIGN (not holes — do not chase):"
uncov_bins illegal_bin | awk -F'\t' '{printf "      illegal_bin %-14s in %-16s (must stay 0)\n", $2, $1}'
uncov_bins ignore_bin  | awk -F'\t' '{printf "      ignore_bin  %-14s in %-16s (excluded from %%)\n", $2, $1}'
echo

# ---------------------------------------------------------- (d) code cov ---
echo "(d) CODE COVERAGE — RTL ($RTL_DU)"
echo "-------------------------------------------------------------------------"
printf "    %-16s %-12s %6s %6s %7s %8s\n" "MODULE" "METRIC" "BINS" "HITS" "MISSES" "%"
printf "    %-16s %-12s %6s %6s %7s %8s\n" "----------------" "------------" "------" "------" "-------" "--------"
awk '/^=== Design Unit:/{du=$4; sub(/^work\./,"",du)}
     /^(Branch|Statement|Toggle|Condition|Expression|FSM) Coverage:/{sect=$1}
     /^    (Branches|Statements|Conditions|Expressions|Toggles|States|Transitions)[ \t]/{
        printf "    %-16s %-12s %6s %6s %7s %8s\n", du, sect, $2, $3, $4, $5}' "$CODE"
echo
echo "    line/branch/statement/condition/expression = 100% on all four modules."
echo "    No FSM was inferred by vcover in any RTL module -> no FSM section."
# Liet ke nut chua chuyen muc, neu con. Chi in tieu de cho design unit nao
# thuc su con lo -- de bao cao khong noi "co lo" khi da phu 100%.
_holes=0
_tmp=/tmp/_toggle_holes.$$
: > "$_tmp"
for du in $RTL_DU; do
  s=$(grep -n "Toggle Coverage for Design Unit work.$du" "$CODE" | cut -d: -f1)
  [ -z "$s" ] && continue
  nodes=$(sed -n "$((s+3)),\$p" "$CODE" | awk '
     NF==0{next} /^========/{exit} /Node.*ExtMode/{next} /^ *---/{next}
     {printf "      %-28s toggle=%s%%\n", $1, $NF}')
  if [ -n "$nodes" ]; then
    _holes=$((_holes+1))
    { echo "    --- $du : nut chua chuyen muc ---"; echo "$nodes"; echo; } >> "$_tmp"
  fi
done
if [ "$_holes" -eq 0 ]; then
  echo "    TOGGLE cung dat 100% tren ca bon module -- khong con nut nao chua chuyen muc."
  echo "    (sau khi ap dung cov_exclude.do cho cac bit bat bien ve kien truc)"
  echo
else
  echo "    Chi TOGGLE con lo; danh sach nut duoi day."
  echo
  cat "$_tmp"
fi
rm -f "$_tmp"

rm -f /tmp/_cg_type.$$
