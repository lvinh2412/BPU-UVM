# Hướng dẫn chạy môi trường kiểm chứng BPU

Mọi lệnh trong tài liệu này đều chạy từ thư mục **`tb/`**.

```bash
cd /home/abc24/work/KLTN_final/bpu_uvm_3/tb
```

Hai công cụ được hỗ trợ song song:

| | Xcelium (Cadence) | QuestaSim (Siemens) |
|---|---|---|
| Makefile | `Makefile` (mặc định) | `Makefile.questa` (phải thêm `-f`) |
| Xem sóng | SimVision | Questa GUI |
| Xem coverage | `imc` | `vsim -viewcov` |

`xrun` **không** có sẵn trong PATH khi mở terminal mới. Trước khi dùng `make`
hay gọi `xrun` trực tiếp, phải nạp môi trường Xcelium:

```bash
source /home/abc24/eda/cadence/xcelium/XCELIUM1803.sh
```

Script này còn đặt `CDS_LIC_FILE` và `UVMHOME` — `run.f` dùng `UVMHOME` ở dòng
`-uvmhome $UVMHOME`, nên thiếu nó thì khâu elaborate hỏng chứ không chỉ là
"không tìm thấy lệnh".

> Riêng `./run_all_xrun.tcl` và `./report_results.tcl` **tự nạp** môi trường này
> (qua `bpu_env.sh`), nên chạy được ngay trong terminal mới. Nếu Xcelium cài ở
> chỗ khác, sửa đường dẫn mặc định trong `bpu_env.sh` hoặc đặt
> `BPU_XCELIUM_SETUP=<đường dẫn script khởi tạo>`.

---

## 1. Chạy một test

### Xcelium

```bash
make build                              # biên dịch + elaborate (làm 1 lần)
make run TESTNAME=rst_state_and_async_test       # chạy 1 test
```

Log ra `sim_<TESTNAME>.log`. Đổi độ chi tiết bằng cách sửa `+UVM_VERBOSITY`
trong `run.f`, hoặc thêm trực tiếp:

```bash
xrun -f run.f +UVM_TESTNAME=rst_state_and_async_test +UVM_VERBOSITY=UVM_HIGH
```

### QuestaSim

```bash
make -f Makefile.questa build
make -f Makefile.questa run TESTNAME=rst_state_and_async_test
```

Log ra `sim_questa_<TESTNAME>.log`.

### Danh sách test

`testlist_44.txt` — 44 test, chia theo 16 nhóm của testplan. Xem tên:

```bash
cat testlist_44.txt
grep carry_ testlist_44.txt      # chỉ nhóm 14 (carry-down)
```

---

## 2. Chạy toàn bộ regression

### Danh sách test

| Tệp | Số test | Nội dung |
|---|---|---|
| `testlist_44.txt` | 44 | 44 mục chức năng của sheet `TestCase` — **mặc định** |

`testlist_44.txt` sinh trực tiếp từ `BPU_Testplan_Hybrid_44.xlsx` nên thứ tự và
cách chia nhóm khớp testplan (1.1 → 16.3, 16 nhóm) — tiện đối chiếu khi viết báo
cáo. Đây là danh sách duy nhất: mọi test trong `tb/tests/` đều thuộc 44 mục này.

> Chú thích trong testlist phải chiếm trọn dòng. Các script chỉ bỏ qua dòng bắt
> đầu bằng `#`, không cắt chú thích giữa dòng.

### Cách 1 — script TCL (khuyến nghị, QuestaSim)

```bash
make -f Makefile.questa build     # bắt buộc build trước
vsim -c -do run_all.do            # mặc định 44 test
vsim -c -do report_results.do     # in bảng kết quả

```

`run_all.do` dùng **một phiên vsim** cho cả bộ test (nạp lại snapshot thay vì
khởi động lại tiến trình mỗi lần), nên nhanh hơn hẳn cách gọi mỗi test một
tiến trình.

Kết quả:

| Tệp | Nội dung |
|---|---|
| `questa_logs/sim_<test>.log` | transcript đầy đủ từng test |
| `run_all_results.txt` | một dòng mỗi test, đầu vào cho `report_results.do` |

Tuỳ chọn qua biến môi trường:

```bash
BPU_TESTLIST=my_list.txt  vsim -c -do run_all.do   # danh sách riêng
BPU_LOGDIR=logs_thu_1     vsim -c -do run_all.do   # thư mục log riêng
BPU_VERBOSITY=UVM_HIGH    vsim -c -do run_all.do   # log chi tiết hơn
BPU_TOP=top_opt_cov BPU_COV=1 vsim -c -do run_all.do   # kèm coverage
```

### Cách 2 — script TCL (Xcelium)

```bash
./run_all_xrun.tcl                # mặc định 44 test, ~3 phút
./report_results.tcl              # in bảng kết quả

```

Hoặc qua Makefile: `make regress` (44), `make report`.

Tương đương `run_all.do` nhưng cho Xcelium. Script tự elaborate một lần rồi
chạy từng test bằng `xrun -R` — chạy lại đúng snapshot trong `xcelium.d`, bỏ
qua khâu kiểm tra phụ thuộc và nạp thư viện (≈3s/test thay vì ≈15s).

Không cần chuẩn bị gì trước: `bpu_env.sh` tự source `XCELIUM1803.sh` nếu thiếu
`xrun`, rồi tìm bản Tcl đóng gói theo Xcelium (`tools.lnx86/tcltk-*`) vì máy
không có `tclsh` hệ thống. Ghi đè bằng `BPU_TCLSH=<đường dẫn tclsh>`.

Kết quả:

| Tệp | Nội dung |
|---|---|
| `xrun_logs/sim_<test>.log` | transcript đầy đủ từng test |
| `xrun_results.txt` | một dòng mỗi test, đầu vào cho `report_results.tcl` |
| `build_xrun.log` | log của bước elaborate |

Tuỳ chọn qua biến môi trường:

```bash
./run_all_xrun.tcl my_list.txt              # danh sách riêng
BPU_ONLY='btb_*'    ./run_all_xrun.tcl      # lọc theo mẫu tên test
BPU_LOGDIR=logs_thu_1 ./run_all_xrun.tcl    # thư mục log riêng
BPU_VERBOSITY=UVM_HIGH ./run_all_xrun.tcl   # log chi tiết hơn
BPU_SEED=12345      ./run_all_xrun.tcl      # cố định seed
BPU_NOBUILD=1       ./run_all_xrun.tcl      # bỏ qua elaborate
BPU_COV=1           ./run_all_xrun.tcl      # kèm coverage (không dùng -R)
```

Mã thoát: `0` nếu tất cả PASS, `1` nếu có FAIL — dùng được cho CI.

> `BPU_COV=1` quay về `xrun -f run.f -coverage all` cho từng test, vì snapshot
> mặc định không có instrument coverage. Chậm hơn nhưng đúng.


> **Lưu ý:** đừng chạy hai job QuestaSim cùng lúc (ví dụ regression và coverage).
> Chúng dùng chung `tr_db.log` trong thư mục hiện tại và có thể giẫm lên nhau.

---

## 3. Bảng báo cáo kết quả

```bash
./report_results.tcl              # không cần trình mô phỏng
vsim -c -do report_results.do     # hoặc dưới QuestaSim
```

Hai lệnh in ra cùng một bảng — `report_results.tcl` chỉ là vỏ bọc chọn nguồn
dữ liệu mặc định rồi gọi lại `report_results.do`, nên không có bản sao logic.
Không truyền đối số thì nó lấy `xrun_results.txt`, thiếu thì `run_all_results.txt`,
thiếu cả hai thì tự quét `xrun_logs/` hoặc `questa_logs/`. Chỉ định thẳng:

```bash
./report_results.tcl run_all_results.txt
```

In bảng gom theo nhóm (chức năng 1.x–14.x / mẫu nhánh 15.x / stress 16.x),
kèm tổng cuối và danh sách test FAIL. Cột `TIME` chỉ hiện khi nguồn dữ liệu có
thời gian chạy (tức bảng do `run_all_xrun.tcl` sinh ra).

Thêm cột đối chiếu với công cụ kia:

```bash
BPU_COMPARE=run_all_results.txt ./report_results.tcl      # xrun so với questa
BPU_COMPARE=ket_qua_questa.txt vsim -c -do report_results.do
```

Cột `DOI CHIEU` hiện kết quả của tệp đối chiếu; dòng nào lệch được đánh dấu
`<<` và liệt kê lại ở cuối. Ví dụ đầu ra:

```
==============================================================================
 TONG: 44 test   43 PASS   1 FAIL
==============================================================================

 TEST FAIL:
   local_pht_counter_and_init_test    FAIL    UVM_ERROR=0 UVM_FATAL=1

 LECH GIUA HAI CONG CU:
   local_pht_counter_and_init_test    nay=FAIL   doi chieu=PASS
```

Nếu chưa có tệp kết quả, script tự quét thư mục log. Nhờ vậy nó đọc được cả log
sinh ra từ luồng khác:

```bash
BPU_LOGDIR=xrun_logs vsim -c -do report_results.do
BPU_LOGDIR=xrun_logs ./report_results.tcl
```

Quy tắc phán xử: lấy **phần tổng kết cuối** của UVM (`UVM_ERROR :` /
`UVM_FATAL :`), không đếm từng dòng lỗi — vì vài test cố ý in thông báo lỗi để
minh hoạ. PASS khi cả hai bằng 0.

---

## 4. Xem dạng sóng

### Xcelium + SimVision

```bash
make wave TESTNAME=carry_across_flush_test
```

Chạy test kèm `shm_dump.tcl` (dump toàn bộ `bpu_hw_top`, kể cả mảng nhớ) rồi mở
SimVision trên `waves.shm`.

Hoặc dùng trực tiếp:

```bash
./wave.sh carry_across_flush_test          # chạy + mở GUI
./wave.sh carry_across_flush_test nogui    # chỉ tạo waves.shm
simvision waves.shm &                      # mở lại sau
```

### QuestaSim GUI

Questa flow không dump sóng sẵn. Chạy có GUI:

```bash
vsim -sv_lib /home/abc24/eda/questa/questaSim/questasim/uvm-1.2/linux_x86_64/uvm_dpi \
     -suppress 3947 +UVM_TESTNAME=rst_state_and_async_test top_opt \
     -do "add wave -r /bpu_hw_top/*; run -all"
```

---

## 5. Coverage

Luồng coverage chạy trên **QuestaSim**.

### Chạy và tạo báo cáo

```bash
# 1. Xoá UCDB cũ  -- BẮT BUỘC nếu covergroup vừa thay đổi
rm -rf cov_work && rm -f cov_*.ucdb merged*.ucdb

# 2. Build bản có instrument coverage (chỉ 4 tệp RTL được đo)
make -f Makefile.questa build_cov

# 3. Chạy toàn bộ test, mỗi test một UCDB
./run_all_cov.sh testlist_44.txt

# 4. Merge + áp loại trừ + sinh báo cáo
make -f Makefile.questa covreport
```

Bước 4 tạo:

| Tệp | Nội dung |
|---|---|
| `cov_report.txt` | tóm tắt + toàn bộ số liệu thô |
| `cov_html/index.html` | báo cáo HTML |
| `merged.ucdb` | gộp thô |
| `merged_excl.ucdb` | đã áp `cov_exclude.do` — dùng cho báo cáo |

> **Bắt buộc xoá UCDB cũ khi sửa covergroup.** Thêm/bớt bin làm đổi *shape* của
> covergroup; UCDB cũ trở nên không tương thích và `vcover merge` sẽ cho số sai
> hoặc báo lỗi.

Xem nhanh con số đầu:

```bash
grep "cg_bpu TOTAL" cov_report.txt
grep -A20 "CODE COVERAGE" cov_report.txt
```

### Chạy coverage cho một test

```bash
make -f Makefile.questa covrun TESTNAME=stress_long_run_hyb_test
```

### Xem coverage bằng GUI

```bash
make -f Makefile.questa covview        # merged.ucdb (toggle CHƯA loại trừ)
make -f Makefile.questa covview_excl   # merged_excl.ucdb (đã loại trừ)
```

Dùng `covview_excl` để khớp với `cov_report.txt`. Bản `covview` cho toggle thấp
hơn vì còn đếm cả các bit bất biến về kiến trúc.

### Về `cov_exclude.do`

38 nút toggle không bao giờ đổi mức vì **lý do kiến trúc**, không phải vì thiếu
kích thích: bit [1:0] của PC/NXPC/NXPC2 (căn từ RV32I), `branch_offset[0]`
(B-immediate luôn chẵn), biến lặp khởi tạo, và các cổng đọc local phía NXPC
không được tầng backstop tiêu thụ. Mỗi dòng loại trừ mang một `-comment` ghi rõ
lý do.

> Trước khi thêm một nút vào tệp này, phải viết được lý do **hình thức** từ RTL
> hoặc từ kiến trúc tập lệnh. "Chưa thấy nó đổi mức" không phải lý do — gần như
> chắc chắn đó là lỗ kích thích. Xem `docs/FINAL_STATUS.md` mục 4.8.

### Coverage bằng Xcelium (tuỳ chọn)

```bash
make covrun TESTNAME=rst_state_and_async_test
make covview TESTNAME=rst_state_and_async_test     # mở imc
```

Luồng chính thức của đề tài là QuestaSim; luồng Xcelium giữ để đối chiếu nhanh.

---

## 6. Dọn dẹp

```bash
make clean                      # sản phẩm Xcelium
make -f Makefile.questa clean   # sản phẩm QuestaSim
```

---

## 7. Trình tự đầy đủ để tái lập số liệu báo cáo

```bash
cd tb

# --- Xcelium ---
make clean && make build
./run_all_xrun.tcl testlist_44.txt

# --- QuestaSim: regression ---
make -f Makefile.questa clean
make -f Makefile.questa build
vsim -c -do run_all.do
cp run_all_results.txt ket_qua_questa.txt

# --- QuestaSim: coverage (chạy SAU khi regression xong) ---
rm -rf cov_work && rm -f cov_*.ucdb merged*.ucdb
make -f Makefile.questa build_cov
./run_all_cov.sh testlist_44.txt
make -f Makefile.questa covreport

# --- Bảng kết quả + đối chiếu hai công cụ ---
BPU_COMPARE=ket_qua_questa.txt vsim -c -do report_results.do
```

Kết quả mong đợi (đã chốt ở Giai đoạn 6):

| | |
|---|---|
| Xcelium | 44 PASS / 0 FAIL |
| QuestaSim | 43 PASS / 1 FAIL |
| Lệch hai công cụ | 1 (`local_pht_counter_and_init_test`, hạn chế H-1) |
| Functional `cg_bpu` | 100.00% (302/302 bin) |
| Code coverage RTL | 100% cả line/branch/statement/condition/expression/toggle |

---

## 8. Tệp liên quan

| Tệp | Nội dung |
|---|---|
| `docs/FINAL_STATUS.md` | trạng thái cuối, hạn chế đã biết, phát hiện về phương pháp |
| `docs/DESIGNNOTES_R1_R2_R3.md` | ba quan sát thiết kế và phần còn lại cần đối chiếu với lõi |
| `BPU_Testplan_Hybrid_44.xlsx` | kế hoạch kiểm chứng; sheet `Ket qua` là bảng trạng thái cuối |
