#!/bin/bash
# Run every test with coverage, one UCDB per test. Does NOT rebuild per test:
# `make covrun` depends on build_cov, which would recompile UVM 97 times, so we
# invoke the same vsim line covrun uses against the already-built top_opt_cov.
#
# A test that fails is recorded and the loop continues.

cd "$(dirname "$0")" || exit 1

QUESTA_ROOT=${QUESTA_ROOT:-/home/abc24/eda/questa/questaSim/questasim}
UVM_DPI=$QUESTA_ROOT/uvm-1.2/linux_x86_64/uvm_dpi
LIST=${1:?usage: run_all_cov.sh <testlist-file>}

: > run_all_status.txt

while read -r t; do
  [ -z "$t" ] && continue
  case "$t" in \#*) continue ;; esac   # testlist_44.txt co dong chu thich
  rm -f "cov_${t}.ucdb"
  vsim -c -sv_lib "$UVM_DPI" -suppress 3947 \
       +UVM_TESTNAME="$t" +UVM_VERBOSITY=UVM_LOW \
       -coverage -onfinish stop top_opt_cov \
       -do "run -all; coverage save cov_${t}.ucdb; quit -f" \
       > "sim_questa_cov_${t}.log" 2>&1
  rc=$?

  log="sim_questa_cov_${t}.log"
  # Counts come from UVM's end-of-run report summary, not from grepping
  # individual messages (a test that prints an expected-error demo would
  # otherwise be miscounted).
  nerr=$(grep -E '^# UVM_ERROR :' "$log" | tail -1 | awk '{print $NF}')
  nfat=$(grep -E '^# UVM_FATAL :' "$log" | tail -1 | awk '{print $NF}')
  : "${nerr:=?}" "${nfat:=?}"

  if [ "$rc" -ne 0 ]; then
    echo "$t FAIL_RC=$rc" >> run_all_status.txt
  elif [ ! -f "cov_${t}.ucdb" ]; then
    echo "$t FAIL_NO_UCDB" >> run_all_status.txt
  elif [ "$nerr" = "?" ]; then
    echo "$t FAIL_NO_UVM_SUMMARY" >> run_all_status.txt
  elif [ "$nerr" != "0" ] || [ "$nfat" != "0" ]; then
    echo "$t FAIL_UVM err=$nerr fatal=$nfat" >> run_all_status.txt
  else
    echo "$t OK" >> run_all_status.txt
  fi
  # Transaction recording DB grows to ~1GB per sweep; drop it between tests.
  rm -f tr_db.log
done < "$LIST"

# Denominator = so dong test that su trong LIST (bo dong trong va dong '#'),
# khong phai tong so dong cua tep.
echo "DONE $(grep -c ' OK$' run_all_status.txt)/$(grep -cvE '^\s*(#|$)' "$LIST")"
