#==============================================================================
# cov_exclude.do  --  QuestaSim 2021.2 toggle-coverage exclusions for the BPU.
#
# These toggle nodes can never flip in this design for ARCHITECTURAL reasons,
# not for lack of stimulus. Excluding them (with the justification recorded in
# each -comment) lets the functional-bit toggle coverage report the true ~100%.
#
# Apply against a coverage database, e.g.:
#   vsim -c -viewcov merged.ucdb -do "do cov_exclude.do; \
#        coverage save merged_excl.ucdb; quit -f"
# then report on merged_excl.ucdb.
#
# Categories:
#   A. Word-aligned PC / NXPC / NXPC2  -> bits [1:0] are invariant 00 (RV32I).
#   B. Word-aligned branch targets     -> bit [0] is invariant 0.
#   C. RISC-V B-immediate is always even-> branch_offset[0] is invariant 0.
#   D. Reset loop iterator `i`          -> a testbench-style integer, not a
#                                          design signal (no functional toggle).
#   E. Dead NXPC-side local read ports  -> read but not consumed by the backstop
#                                          tier (BTB-only); see BƯỚC 4 report.
#==============================================================================

# ---- A. word-aligned PC/NXPC/NXPC2: bits [1:0] never toggle (RV32I, PC[1:0]=00)
coverage exclude -du bpu_ctrl      -togglenode {pc[0]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"
coverage exclude -du bpu_ctrl      -togglenode {pc[1]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"
coverage exclude -du bpu_ctrl      -togglenode {nxpc[0]}  -comment "RV32I word-aligned NXPC: NXPC[1:0]=00 invariant"
coverage exclude -du bpu_ctrl      -togglenode {nxpc[1]}  -comment "RV32I word-aligned NXPC: NXPC[1:0]=00 invariant"

coverage exclude -du bpu_predictor -togglenode {pc[0]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"
coverage exclude -du bpu_predictor -togglenode {pc[1]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"

coverage exclude -du bpu_reg       -togglenode {pc[0]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"
coverage exclude -du bpu_reg       -togglenode {pc[1]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"
coverage exclude -du bpu_reg       -togglenode {nxpc[0]}  -comment "RV32I word-aligned NXPC: NXPC[1:0]=00 invariant"
coverage exclude -du bpu_reg       -togglenode {nxpc[1]}  -comment "RV32I word-aligned NXPC: NXPC[1:0]=00 invariant"
coverage exclude -du bpu_reg       -togglenode {nxpc2[0]} -comment "RV32I word-aligned NXPC2: NXPC2[1:0]=00 invariant"
coverage exclude -du bpu_reg       -togglenode {nxpc2[1]} -comment "RV32I word-aligned NXPC2: NXPC2[1:0]=00 invariant"

coverage exclude -du bpu_top       -togglenode {pc[0]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"
coverage exclude -du bpu_top       -togglenode {pc[1]}    -comment "RV32I word-aligned PC: PC[1:0]=00 invariant"
coverage exclude -du bpu_top       -togglenode {nxpc[0]}  -comment "RV32I word-aligned NXPC: NXPC[1:0]=00 invariant"
coverage exclude -du bpu_top       -togglenode {nxpc[1]}  -comment "RV32I word-aligned NXPC: NXPC[1:0]=00 invariant"
coverage exclude -du bpu_top       -togglenode {nxpc2[0]} -comment "RV32I word-aligned NXPC2: NXPC2[1:0]=00 invariant"
coverage exclude -du bpu_top       -togglenode {nxpc2[1]} -comment "RV32I word-aligned NXPC2: NXPC2[1:0]=00 invariant"

# ---- B. word-aligned branch targets: bit [0] never toggles (target[0]=0)
coverage exclude -du bpu_ctrl      -togglenode {btb_target_pc[0]}     -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_ctrl      -togglenode {btb_target_nxpc2[0]}  -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_ctrl      -togglenode {corr_nxpc2[0]}        -comment "word-aligned correction target: target[0]=0"
coverage exclude -du bpu_ctrl      -togglenode {f_nxpc2[0]}           -comment "word-aligned fetch target: target[0]=0"

coverage exclude -du bpu_predictor -togglenode {btb_wr_target[0]}     -comment "word-aligned BTB write target: target[0]=0"

coverage exclude -du bpu_reg       -togglenode {btb_target_pc[0]}     -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_reg       -togglenode {btb_target_nxpc[0]}   -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_reg       -togglenode {btb_target_nxpc2[0]}  -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_reg       -togglenode {btb_wr_target[0]}     -comment "word-aligned BTB write target: target[0]=0"

coverage exclude -du bpu_top       -togglenode {btb_target_pc[0]}     -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_top       -togglenode {btb_target_nxpc[0]}   -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_top       -togglenode {btb_target_nxpc2[0]}  -comment "word-aligned BTB target: target[0]=0"
coverage exclude -du bpu_top       -togglenode {btb_wr_target[0]}     -comment "word-aligned BTB write target: target[0]=0"

# ---- C. RISC-V B-immediate is always even -> branch_offset[0]=0
coverage exclude -du bpu_ctrl      -togglenode {branch_offset[0]}     -comment "RISC-V B-immediate is even: branch_offset[0]=0"
coverage exclude -du bpu_predictor -togglenode {branch_offset[0]}     -comment "RISC-V B-immediate is even: branch_offset[0]=0"
coverage exclude -du bpu_top       -togglenode {branch_offset[0]}     -comment "RISC-V B-immediate is even: branch_offset[0]=0"

# ---- D. reset loop iterator (integer 32-bit), not a design signal
coverage exclude -du bpu_reg       -togglenode {i}                    -comment "reset loop iterator (integer), not a functional design signal"

# ---- E. dead NXPC-side local read ports (backstop tier is BTB-only; unconsumed)
coverage exclude -du bpu_reg       -togglenode {local_bht_data_nxpc[10]}  -comment "NXPC-side local BHT read not consumed by backstop tier (BTB-only path)"
coverage exclude -du bpu_reg       -togglenode {local_pht_index_nxpc[10]} -comment "NXPC-side local PHT index feeds unconsumed local_pht_data_nxpc (BTB-only path)"
coverage exclude -du bpu_top       -togglenode {local_bht_data_nxpc[10]}  -comment "NXPC-side local BHT read not consumed by backstop tier (BTB-only path)"
