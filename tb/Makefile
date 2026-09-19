SHELL := /bin/bash

TESTNAME ?= rst_state_and_async_test

build:
	xrun -f run.f -elaborate 2>&1 | tee build.log

run:
	xrun -f run.f +UVM_TESTNAME=$(TESTNAME) 2>&1 | tee sim_$(TESTNAME).log

all: build run

# ---- Regression (xem docs/HOWTO_RUN.md muc 2) ----
# make regress            -> 44 muc chuc nang cua testplan
# make regress LIST=x.txt -> danh sach khac
# make report             -> in bang PASS/FAIL cua luot chay gan nhat
LIST ?= testlist_44.txt

regress:
	./run_all_xrun.tcl $(LIST)

report:
	./report_results.tcl

wave:
	xrun -f run.f +UVM_TESTNAME=$(TESTNAME) -input shm_dump.tcl 2>&1 | tee sim_$(TESTNAME).log
	simvision waves.shm &

clean:
	rm -rf *.log *.wlf *.ini *.dbg transcript work/ xcelium.d/ xrun.history \
	       INCA_libs/ waves.shm/ cov_work/ .simvision/ tr_db.log \
	       xmsim.key xmelab.key xmvlog.key xmsim.log xmelab.log xmvlog.log

src:
	source /home/abc24/eda/cadence/xcelium/XCELIUM1803.sh

covrun:
	xrun -f run.f +UVM_TESTNAME=$(TESTNAME) -coverage all -covoverwrite -covtest $(TESTNAME) 2>&1 | tee sim_cov_$(TESTNAME).log

covview:
	imc -load cov_work/scope/$(TESTNAME) &
