# Trạng thái cuối — môi trường kiểm chứng BPU hybrid

*Chốt sau Giai đoạn 6. Mọi con số trong tài liệu này là số đo thực, tái lập được
bằng `make build` + `run_all_xrun.tcl` (Xcelium) / `run_all.do` (QuestaSim) với
`testlist_44.txt`.
Đây là nguồn cho phần "Hạn chế và hướng phát triển" của luận văn.*

---

## 1. Số test cuối cùng

**44 test** trong `tb/testlist_44.txt` — đúng 44 mục của sheet `TestCase` trong
`tb/BPU_Testplan_Hybrid_44.xlsx`.

| Nhóm testplan | Số test | xrun | QuestaSim |
|---|---|---|---|
| 1. Reset & Init | 2 | 2 PASS | 2 PASS |
| 2. Halt | 2 | 2 PASS | 2 PASS |
| 3. BTB | 3 | 3 PASS | 3 PASS |
| 4. Local PHT (Pshare) | 4 | 4 PASS | 3 PASS, 1 FAIL |
| 5. Global PHT (Gshare) | 4 | 4 PASS | 4 PASS |
| 6. Choice | 4 | 4 PASS | 4 PASS |
| 7. GHR | 1 | 1 PASS | 1 PASS |
| 8. Dự đoán tại tầng fetch | 2 | 2 PASS | 2 PASS |
| 9. Pre-compute & Gating | 1 | 1 PASS | 1 PASS |
| 10. Flush Logic | 2 | 2 PASS | 2 PASS |
| 11. Tầng chuyển hướng | 3 | 3 PASS | 3 PASS |
| 12. Correction | 2 | 2 PASS | 2 PASS |
| 13. Output MUX | 1 | 1 PASS | 1 PASS |
| 14. Carry-down pipeline | 4 | 4 PASS | 4 PASS |
| 15. Branch Pattern | 6 | 6 PASS | 6 PASS |
| 16. Stress / Random | 3 | 3 PASS | 3 PASS |
| **Tổng** | **44** | **44 PASS / 0 FAIL** | **43 PASS / 1 FAIL** |

Lệch duy nhất giữa hai công cụ: `local_pht_counter_and_init_test` (mục 4.2) —
xem hạn chế H-1.

---

## 2. Hạn chế đã biết

### H-1. Mục 4.2 chỉ chạy được trên Xcelium

`local_pht_counter_and_init_test` pha D phải **ghim** `local_bht[64] = 0` xuyên
suốt 8 nhánh: mỗi lần cập nhật, RTL ghi lịch sử đã dịch vào ô đó, nên nếu chỉ
`deposit` một lần thì từ nhánh thứ hai chỉ mục đã rời khỏi 0 và pha D không còn
quan sát được một bộ đếm duy nhất. Việc ghim bắt buộc dùng `uvm_hdl_force` trên
**phần tử của mảng không gói**.

Đo được: QuestaSim trả `rc = 0` cho `uvm_hdl_force`/`uvm_hdl_release` trên phần
tử mảng (`vsim-16133`), trong khi `read` và `deposit` chạy bình thường; Xcelium
chấp nhận cả bốn thao tác.

| dạng đường dẫn | read | force | release | deposit |
|---|---|---|---|---|
| vô hướng (`ghr`) | 1 | 1 | 1 | 1 |
| phần tử mảng không gói | 1 | **0** (Q) | **0** (Q) | 1 |
| net của interface | 1 | 1 | 1 | 1 |

Từ Giai đoạn 4, backdoor kiểm mã trả về và phát `uvm_fatal` kèm đường dẫn HDL cụ
thể, nên trên Questa test **dừng ngay với thông báo rõ ràng** thay vì âm thầm
chạy sai. Đây là hạn chế của công cụ, không phải của thiết kế.

*Hướng xử lý nếu cần chạy trên Questa:* nạp lại giá trị bằng `deposit` trước mỗi
nhánh thay vì ghim một lần. Cách này mô phỏng được hiệu quả của force nhưng làm
thay đổi cấu trúc kịch bản, nên chưa áp dụng.

### H-2. Ba mục hạ mức scoreboard

| Mục | Lý do |
|---|---|
| 4.3 `pshare_index_two_stage` | ghim `local_bht`/`local_pht` để có hai lịch sử khác nhau tại `pc` và `nxpc2` trong cùng chu kỳ |
| 5.1 `gshare_index_and_skew` | ghim GHR để cô lập chỉ mục gshare |
| 14.2 `carry_paths_and_gating_scope` | ép `btb_valid[64] = 1`; reference cho `d_valid = 1` còn DUT cho `d_valid = 0`, hai bên đánh giá tầng backstop khác nhau |

Ba mục này gọi `scoreboard_not_applicable()`: mức báo cáo của scoreboard hạ
xuống `UVM_INFO`, và phép kiểm thật nằm ở các `chk()` đọc backdoor. **41/44 mục
còn lại giữ scoreboard sống.**

### H-2b. Độ phủ cuối cùng

| | Kết quả |
|---|---|
| Functional `cg_bpu` | **100.00%** — 302/302 bin, 0 bin thiếu |
| Code — `bpu_reg` | line/branch/statement/condition/expression **100%**, toggle **100%** (682/682) |
| Code — `bpu_predictor` | line/branch/statement/condition/expression **100%**, toggle **100%** (338/338) |
| Code — `bpu_ctrl` | line/branch/statement/expression **100%**, toggle **100%** (706/706) |
| Code — `bpu_top` | toggle **100%** (738/738) |

Phạm vi báo cáo giới hạn ở bốn tệp RTL (`-du` filter trong `Makefile.questa`);
mã testbench không được đo. `vcover` không suy ra FSM nào nên không có mục FSM.

Toggle đạt 100% **sau khi áp `cov_exclude.do`** cho các bit bất biến về kiến
trúc (38 nút): PC/NXPC/NXPC2 bit [1:0] căn từ theo RV32I, `branch_offset[0]`
luôn 0 theo B-immediate của RISC-V, biến lặp khởi tạo `i`, và các cổng đọc
local phía NXPC không được backstop tiêu thụ. Mỗi dòng loại trừ mang một
`-comment` ghi lý do.

**Không còn nút nào chưa chuyển mức ngoài danh sách loại trừ đó.** Hai lỗ cuối
cùng được vá ở lô này đều là **lỗ kích thích**, không phải bất biến kiến trúc —
xem 4.8.

### H-3. Mười bin coverage bị loại vì bất khả thi về hình thức

Chỉ ở `cx_tier_x_corr`. Hai coverpoint của cross này được điều khiển bởi **cùng
một tín hiệu**:

- `bpu_ctrl.v:98-102`: `corr_valid` có ưu tiên cao nhất trong MUX, nên
  `s_redirect_tier == correction` ⟺ `corr_valid`;
- `s_corr_kind != none` ⟺ `corr_valid` (theo cách đặt trong `bpu_coverage.sv`).

Hai vế đều tương đương với `corr_valid` nên luôn đi cùng nhau. Suy ra
`<correction, none>` và 9 tổ hợp `<none|fetch|backstop, X≠none>` là bất khả thi —
loại bằng `ignore_bins` kèm lý do hình thức, **không** loại vì "chưa hit".

Không cross nào khác có bin bất khả thi chưa được xử lý; ba `ignore_bins` có sẵn
từ trước (`cx_branch_x_taken`, `cx_flush_x_branch`, `cx_tier_x_flush`,
`cx_btb_nxpc2_x_predict_nxpc2`) đã được rà lại và vẫn đúng.

---

## 3. DesignNotes R1, R2, R3

Chi tiết đầy đủ ở `docs/DESIGNNOTES_R1_R2_R3.md`. Tóm tắt:

| | Tái hiện ở mức module | Bằng chứng | Phần còn lại cần đối chiếu với lõi |
|---|---|---|---|
| **R1** tầng fetch chuyển hướng không kiểm opcode; BTB không có tag | **Có**, ba mục độc lập | 8.2 (5/5 địa chỉ cách 4 KB cho cùng kết quả), 9.1(c), 15.5 (**20/20** lần chuyển hướng nhầm với địa chỉ không phải lệnh rẽ) | Lõi có tầng lọc nào nữa không; chi phí mỗi lần; tần suất thực tế |
| **R2** carry-down không bị xoá khi flush | **Không** tái hiện được hệ quả xấu | 14.3 ba pha | Hợp đồng với lõi: lệnh đã bị flush không được tới execute với `is_branch = 1` |
| **R3** `flush=1` đồng thời `corr_valid=1` | **Có**, điều kiện đã xác định đủ | 12.2 pha B (`corr_nxpc2 = 0x554` đúng kỳ vọng) | Một bong bóng có đủ để lõi áp dụng địa chỉ hiệu chỉnh không |

Cả ba đều có phần phụ thuộc RTL lõi mà kiểm chứng mức module không trả lời được.
Không mục nào kết luận thiết kế sai.

---

## 4. Những phát hiện về phương pháp

Bốn phát hiện dưới đây đều là **lỗi của môi trường kiểm chứng, không phải của
thiết kế**. Chúng đáng ghi lại vì mỗi cái đều từng tạo ra một con số sai mà
không ai nghi ngờ.

### 4.1. Số liệu cũ sai vì giới hạn testbench, không vì thiết kế

Ba ví dụ đo được:

- **`max_consecutive_flush` = 1.** Giao thức driver 2 chu kỳ làm `is_branch` đảo
  1,0,1,0; `bpu_ctrl.v:68` ép `flush = 0` khi `is_branch = 0`, nên số bong bóng
  liên tiếp bị **chặn cứng ở 1** bất kể thiết kế. P19 và P28 vì thế bị đánh dấu
  "BỊ CHẶN" trong kế hoạch. Bộ sinh nhất quán đường ống lái back-to-back đã gỡ
  chặn: P19 đo được **10**, P28 đo được **16**.
- **Ngưỡng 5% của mẫu tương quan.** Ghi chú cũ kết luận "<5% không đạt được".
  Kết luận đó đúng **với kích thích cũ** (nhánh sát nhau, xem 4.4) nhưng sai với
  kích thích đúng: đo được **1.0%** với 800 cặp.
- **32 FAIL so với 25 thực đo.** Con số FAIL trước migration phản ánh kích thích
  không lái `nxpc2`, chứ không phải lỗi RTL.

### 4.2. Test PASS mà không kiểm gì, do backdoor nuốt mã lỗi

`bpu_backdoor.sv` bỏ qua mã trả về của `uvm_hdl_*` bằng `void'(...)`. Trên
Questa, `force` trên phần tử mảng trả `rc = 0` nên cảnh **không bao giờ được
dựng**, mà test vẫn chạy tiếp. Hai test — `gshare_aliasing_test` và
`local_bht_shift_12b_test` — **PASS trong khi không kiểm gì**: phép kiểm của
chúng tình cờ vẫn đúng với trạng thái mặc định.

Sửa: mọi lời gọi DPI đi qua bốn wrapper kiểm rc và phát `uvm_fatal` kèm đường
dẫn HDL. Dùng `uvm_fatal` chứ không `uvm_error` vì một cảnh dựng thất bại làm
mọi phép kiểm sau đó vô nghĩa; chạy tiếp chỉ tạo kết quả gây hiểu nhầm.

### 4.3. Hai vế so sánh dùng hai nguồn khác loại (P11/P12)

P12 báo *"tournament 66.0% < always-global 69.8%"* và FAIL. Nhưng 66.0% tính từ
`mispredicts` (nguồn **carry-down**) còn 69.8% tính từ `read_global_pht_pc` tại
tầng execute — một ô **khác** tại một thời điểm **khác**. Đọc tại execute là đọc
*hậu nghiệm*: `local_bht` và `ghr` đã tiến lên nên ô được đọc không phải ô bộ dự
đoán đã dùng, và nó thiên vị có hệ thống.

Mức thiên vị đo được: trên 16.2 là +2.5 điểm với local và **+10.1 điểm** với
global; trên chính P12 là **+35.3 điểm** với global (carry-down 34.5% so với
69.8%). **Thứ hạng đảo ngược**: nguồn đúng cho local thắng, nguồn cũ cho global
thắng. Sau khi lấy cả ba vế từ carry-down, P11/P12 PASS với tournament 81.3% so
với local 69.2% và global 76.5%.

### 4.4. Bậc thang tại hai chu kỳ, do cập nhật tại execute

`local_pht_wr_en` / `global_pht_wr_en` / `choice_wr_en` và đường ghi GHR đều lấy
`is_branch` làm wr_en, tức chỉ ghi ở tầng **EXECUTE** — hai chu kỳ sau khi cùng
nhánh đó được tra ở tầng FETCH. Lái các nhánh sát nhau thì mọi lần tra đều nhìn
trạng thái cũ hai nhánh.

Đây là **bậc thang, không phải đường dốc**:

| khoảng cách | vòng lặp chu kỳ 5 | nhánh B của cặp tương quan |
|---|---|---|
| 0 chu kỳ | 40.00% | 50.50% |
| 1 chu kỳ | 40.00% | 50.50% |
| 2 chu kỳ | **0.00%** | **3.50%** |

Một chu kỳ nghỉ không mua được gì vì lệnh ghi rơi đúng tại T+2. **Cả 28 test
hiệu năng bản cũ đều chạy ở khoảng cách 1** — tức nằm trọn trong vùng xấu mà
không ai biết.

Hệ quả về phương pháp: khoảng cách nhánh là **tham số đo**, không phải chi tiết
triển khai. Một con số "tỉ lệ đoán sai" không kèm khoảng cách thì không so sánh
được với bất cứ con số nào khác. Độ nhạy tập trung ở **global** (+28.96 điểm khi
đổi từ gap 0 sang gap 2) vì chỉ mục gshare phụ thuộc GHR — trạng thái đổi nhanh
nhất; local gần như bất động (+0.21 điểm).

### 4.5. Hai điểm đo BTB không được gộp

`btb_valid_nxpc2` (tra theo địa chỉ ở tầng FETCH) quyết định có đạt 0 bong bóng
hay không; `btb_valid_pc` (tra theo `pc` tại tầng EXECUTE) quyết định PHT khởi
tạo WT hay cập nhật bộ đếm. Hai số tra ở **hai chỉ mục khác nhau tại hai thời
điểm khác nhau**. Gộp chúng là mất thông tin.

Ngoài ra, chuẩn hoá phía fetch phải theo **nhánh**, không theo **chu kỳ**: mẫu số
theo chu kỳ gồm cả chu kỳ nghỉ nên trần của nó chỉ là 33% khi khoảng cách nhánh
là 2. Giá trị đúng lấy qua `cd_hit` — chính là `btb_valid_nxpc2` trễ hai chu kỳ.

### 4.6. Bộ sinh ngẫu nhiên phải tự chứng minh nó đúng

Phép tự kiểm đầu tiên của mục 16.1 chỉ đếm số chu kỳ tầng fetch thắng MUX. Thử
nghiệm đối chứng — ghim `nxpc2` về một địa chỉ cố định, đúng kiểu hỏng của ba
test cũ — vẫn cho **247 lần thắng**, vì một địa chỉ cố định sau một lúc cũng
thành một ô BTB hợp lệ. Phép đếm đó **không đủ**.

Phép kiểm đúng là bất biến địa chỉ, đọc lại từ **net của interface**:
`nxpc2(T) == nxpc(T+1) == pc(T+2)`. Cùng phép phá hoại đó, bất biến bắt được ngay
từ bộ ba đầu tiên (976/2176 so với 2201/2201 khi sạch).

Bài học chung: một bộ sinh so mô hình nội bộ của chính nó với chính nó thì không
chứng minh được gì — phải đọc lại từ tín hiệu thật.

### 4.7. Bộ sinh số ngẫu nhiên của SV không khả chuyển

`$urandom_range` là implementation-defined: Xcelium và QuestaSim sinh chuỗi khác
nhau từ cùng một seed danh nghĩa. Hai test tiêu thụ `pat_correlated_mcseq` vì thế
là hai phép tung đồng xu (6/12 và 3/10 seed PASS), và sự khác biệt trông giống
một khác biệt giữa hai công cụ trong khi không phải.

Sửa: LCG 32 bit tính bằng số học SV thông thường (`tb/tests/bpu_det_rng.sv`) —
tràn giống hệt nhau trên mọi trình mô phỏng. Bằng chứng: quét seed 1..8 cho kết
quả **trùng khớp từng seed** giữa hai công cụ.

---

### 4.8. Lỗ độ phủ có thể là lỗ kích thích đội lốt bất biến kiến trúc

Hai lỗ toggle cuối cùng, phát hiện ở lô dọn dẹp, đều **trông giống** bất biến
kiến trúc nhưng không phải:

- **Bit cao của các bus địa chỉ** (`btb_target_nxpc2[13-29]`, `bpu_nxpc2[22]`,
  `corr_nxpc2[16]`, …) không chuyển mức vì bộ sinh ngẫu nhiên của mục 16.1 chỉ
  rút `pc[11:2]` — nghĩ rằng dải `0x000–0xFFF` là đủ. Nhưng `cp_pc_region` lấy
  `pc[31:22]`, tức chia **không gian 32 bit** thành ba vùng, nên cả dải đó rơi
  trọn vào `low_mem`. Sửa: rút `pc[31:12]` ngẫu nhiên hoàn toàn, giữ `pc[11:2]`
  trong 1024 ô để chỉ mục vẫn lặp lại (BTB vẫn trúng). Việc này đồng thời lấp
  năm bin của `cx_pc_region_x_tier`, hai bin của `cx_pc_region_x_btb` và một
  bin của `cp_btb_target_value`.
- **`btb_target_nxpc2[1]`** không chuyển mức vì bộ sinh rút offset là
  `{rnd(256), 2'b00}` — ép luôn bit 1 về 0. Ràng buộc thật chỉ là bit **0** = 0
  (B-immediate của RISC-V luôn chẵn). Sửa: `{rnd(512), 1'b0}`.

Bài học: trước khi ghi một nút vào danh sách loại trừ, phải viết được lý do
**hình thức** từ RTL hoặc từ kiến trúc tập lệnh. Nếu lý do duy nhất là "chưa
thấy nó chuyển mức" thì gần như chắc chắn đó là lỗ kích thích.

---

## 5. Bảng đối chiếu hai công cụ

Bảng ba cột (tên test, xrun, QuestaSim) kèm cột đánh dấu lệch — 44 dòng, một
dòng mỗi test. Sinh bằng `run_all_xrun.tcl` và `run_all.do` rồi đối chiếu bằng
`BPU_COMPARE=... ./report_results.tcl`.
