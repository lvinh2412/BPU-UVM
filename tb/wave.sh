#!/bin/bash
# wave.sh — chạy 1 test BPU với waveform dump và mở SimVision
#
# Cách dùng:
#   ./wave.sh                       # chạy rst_state_and_async_test (mặc định)
#   ./wave.sh halt_carry_freeze_test # chạy test khác
#   ./wave.sh carry_across_flush_test # chạy test khác
#   ./wave.sh rst_state_and_async_test nogui # chạy không mở GUI (chỉ tạo waves.shm)
#
# Yêu cầu trước:
#   - shm_dump.tcl đã tồn tại trong cùng thư mục
#   - run.f đã có -access +rwc
#   - Đứng ở thư mục tb/

set -e  # exit on error

# ----- Tham số -----
TESTNAME=${1:-rst_state_and_async_test}    # mặc định: rst_state_and_async_test
NOGUI=${2:-gui}                    # mặc định: mở GUI; truyền "nogui" để tắt

# ----- Kiểm tra môi trường -----
if [ ! -f run.f ]; then
  echo "ERROR: không thấy run.f. Đứng đúng thư mục tb/ trước khi chạy."
  exit 1
fi

if [ ! -f shm_dump.tcl ]; then
  echo "Tạo shm_dump.tcl tự động..."
  cat > shm_dump.tcl << 'EOF'
database -open waves -into waves.shm -default
probe -create -shm bpu_hw_top -all -depth all
run
exit
EOF
fi

# ----- Clean snapshot cũ -----
echo ">>> Cleaning previous snapshot..."
rm -rf xcelium.d xrun.log INCA_libs waves.shm cov_work

# ----- Chạy simulation -----
echo ">>> Running test: $TESTNAME"
echo ">>> Logging to: sim_${TESTNAME}.log"

xrun -f run.f +UVM_TESTNAME=${TESTNAME} -input shm_dump.tcl 2>&1 \
  | tee sim_${TESTNAME}.log

# ----- Tóm tắt kết quả -----
echo ""
echo "============ RESULT SUMMARY ============"
grep -E "UVM_ERROR :|UVM_FATAL :|UVM_WARNING :|PASSED|FAILED|Miscompares \(total\)" \
  sim_${TESTNAME}.log | tail -10
echo "========================================"

# ----- Verify waveform output -----
if [ -d waves.shm ]; then
  WAVE_SIZE=$(du -sh waves.shm | cut -f1)
  echo ">>> waves.shm created (size: ${WAVE_SIZE})"
else
  echo "WARNING: waves.shm not created! Check sim_${TESTNAME}.log for errors."
  exit 1
fi

# ----- Mở SimVision (nếu không phải nogui) -----
if [ "$NOGUI" != "nogui" ]; then
  echo ">>> Opening SimVision..."
  simvision waves.shm &
  echo ">>> SimVision started in background (PID $!)"
else
  echo ">>> Skipping SimVision (nogui mode)"
  echo ">>> To open later: simvision waves.shm &"
fi
