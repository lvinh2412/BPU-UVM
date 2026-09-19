# Chuyen doi moi truong UVM cua BPU: tu hai UVC sang mot agent

Bao cao ky thuat. Moi con so trong tai lieu nay lay tu bao cao do that; cho nao
chua do thi ghi ro "chua do".

---

## 1. Tom tat dieu hanh

**Truoc.** Testbench dung hai UVC doc lap. `bpu_predict` lai 7 chan phia fetch
va lay mau 3 chan ngo ra; `bpu_update` lai 3 chan phia execute. Mot virtual
sequencer (`bpu_mcsequencer`) giu handle toi hai sequencer that, va moi kich
thich mot chu ky phai la mot virtual sequence dung `fork...join` de hai item roi
vao cung mot canh clock. Mo hinh tham chieu phai ghep doi hai luong item bang
hai lenh `get()` lockstep.

**Sau.** Mot agent duy nhat (`bpu_agent`) lai ca 10 chan vao va lay mau ca 13
tin hieu trong mot anh chup. Khong con virtual sequencer, khong con
`p_sequencer`, khong con `fork...join` o tang kich thich. Mo hinh tham chieu
nhan mot item mot chu ky.

**Ket qua do duoc.**

| Phep do | Ket qua |
|---|---|
| Hoi quy Xcelium | **44/44 PASS** |
| Ba cot scoreboard tren 44 test | 40/44 khop tuyet doi, 4 dong lech da truy nguyen nhan |
| Functional coverage | **302/302 bin**, **tap bin giong het baseline theo ten, hai chieu deu rong** |
| Code coverage | **100%** moi metric tren 4 design unit RTL, bang so lieu khop tung ky tu |
| Dau vet chan theo chu ky | do tren 9 test; **7 test khop bit-exact**, 2 test lech dung 1 dong |
| Test phai fatal | `local_pht_counter_and_init_test` fatal y het, duong dan HDL khong doi |
| RTL | khong sua mot dong (`diff -r` rong) |

**Hai sai lech duoc chap nhan.** Ca hai da truy ra co che va chung minh vo hai
bang so lieu; chi tiet o muc 6.

- **R6** — cua so `force` 2ns o hai test khong con trum posedge nao, nen monitor
  khong lay mau chu ky bi force. Hau qua: dau vet lech dung 1 dong moi test,
  va so miscompare giam tu 1 xuong 0. **Coverage khong mat bin nao.**
- **R8** — hai test di duong `mcseq` co them dung 1 chu ky trong cua so drain.
  Kich thich khop tung dong; chu ky kich thich cuoi cung bang nhau o hai ban.

**Tong dong nguon:** 12985 -> 12572 (giam **413 dong**, khoang 3.2%).

---

## 2. Bang thay doi cap tep

### 2.1 Tep THEM — `bpu_agent/` (10 tep, 1473 dong)

| Tep | Dong | Vai tro |
|---|---:|---|
| `bpu_if.sv` | 292 | 13 tin hieu, `drive_bpu_input()` 10 tham so, `sample_bpu_all()` 13 tham so, `bpu_reset()`, `park_bus()`, 7 assertion |
| `bpu_item.sv` | 122 | 10 truong `rand` + 3 truong quan sat `UVM_NOCOMPARE`, 6 rang buoc |
| `bpu_monitor.sv` | 69 | mot item moi chu ky, mang du 13 tin hieu |
| `bpu_sequencer.sv` | 21 | `uvm_sequencer #(bpu_item)` |
| `bpu_seqs.sv` | 546 | `bpu_base_seq` + 14 sequence tien ich (ma chet, giu de khong mat tinh nang) |
| `bpu_driver.sv` | 105 | lai 10 chan, kem watchdog do bus |
| `bpu_agent.sv` | 47 | monitor + sequencer + driver |
| `bpu_env.sv` | 26 | boc agent |
| `bpu_drive_seqs.sv` | 229 | `bpu_drive_seq` (13 knob) + 3 sequence quet (ma chet) |
| `bpu_pkg.sv` | 16 | `typedef bpu_vif_config` + include theo thu tu phu thuoc |

### 2.2 Tep XOA (20 tep, 1932 dong)

| Nhom | Tep | Dong |
|---|---:|---:|
| `bpu_predict/` | 9 | 967 |
| `bpu_update/` | 9 | 889 |
| `tb/bpu_mcsequencer.sv` | 1 | 26 |
| `tb/bpu_mcseqs_lib.sv` | 1 | 50 |
| **Tong** | **20** | **1932** |

### 2.3 Tep SUA (22 tep)

**Tang lap rap va build**

| Tep | +them | -xoa | Mo ta |
|---|---:|---:|---|
| `tb/bpu_hw_top.sv` | 41 | 22 | mot the hien `bpu_if` thay hai; noi lai 15 cong DUT; them khoi `BPU_PIN_TRACE` |
| `tb/bpu_tb_top.sv` | 4 | 10 | import `bpu_pkg`; 2 lenh `config_db::set` thay 4; bo 2 `include` |
| `tb/bpu_tb.sv` | 9 | 17 | 3 component thay 4; 1 noi TLM thay 2 |
| `tb/run.f` | 4 | 9 | `-incdir ../bpu_agent`; 2 tep thay 4 |
| `tb/Makefile.questa` | 4 | 7 | `INCDIRS`, `SV_IF`, `SV_PKG` |

**Tang kiem tra**

| Tep | +them | -xoa | Mo ta |
|---|---:|---:|---|
| `bpu_module/bpu_reference.sv` | 62 | 67 | mot `item_fifo`; `main_loop` mot `get()`; 3 chu ky ham; 67 cho `p.`/`u.` -> `it.` |
| `bpu_module/bpu_scoreboard.sv` | 11 | 11 | `predict_fifo` -> `item_fifo`; doi kieu tham so |
| `bpu_module/bpu_module_env.sv` | 8 | 14 | mot `bpu_item_export` thay hai; 2 lenh `connect` thay 3 |
| `bpu_module/bpu_backdoor.sv` | 6 | 2 | **chi 2 chuoi duong dan** + 4 dong chu thich |
| `bpu_module/bpu_module_pkg.sv` | 2 | 3 | `import bpu_pkg` |
| `bpu_module/bpu_expected_item.sv` | 1 | 1 | chu thich |

**Tang kich thich va test**

| Tep | +them | -xoa | Mo ta |
|---|---:|---:|---|
| `tb/bpu_drive_vseqs.sv` | 94 | 54 | 2 sequence: `bpu_base_seq`, `deassert_after`, 2 item, bo `fork...join` |
| `tb/bpu_pipe_helper.sv` | 32 | 34 | kieu `m_seqr`; gop 2 `start` thanh 1 |
| `tests/hyb_btb_tests.sv` | 14 | 8 | `start` tren sequencer moi; `#5ns`->`#1ns` (2 cho) |
| `tests/global_pht_tests.sv` | 7 | 2 | `#5ns`->`#1ns` (ban sao thu hai cua `drive_branch`) |
| `tests/stress_tests.sv` | 5 | 5 | `extends bpu_base_seq`; `start(m_sequencer, this)` |
| `tests/hyb_predict_tests.sv` | 4 | 4 | kieu `pvif`; duong dan component |
| `tests/hyb_carry_tests.sv` | 2 | 2 | `h.connect(...)` |
| `tests/hyb_stress_tests.sv` | 2 | 2 | `gen.connect(...)` |
| `tests/hyb_pht_ghr_tests.sv` | 1 | 1 | `h.connect(...)` |
| `tests/hyb_pattern_tests.sv` | 1 | 1 | chu thich |
| `tests/bpu_coherent_gen.sv` | 1 | 1 | chu thich |

### 2.4 Tep KHONG DOI

| Nhom | So tep |
|---|---:|
| `rtl/` | 4 (`diff -r` rong) |
| `clock_and_reset/` | 10 |
| `tests/hyb_choice_tests.sv`, `hyb_rst_halt_tests.sv`, `hyb_redirect_tests.sv`, `global_pht_extra_tests.sv`, `bpu_det_rng.sv` | 5 |

### 2.5 Tong

| | bpu_uvm_3 | bpu_uvm_4 | Chenh |
|---|---:|---:|---:|
| Tong dong nguon (`.sv` + `.v`) | 12985 | 12572 | **-413** |

---

## 3. Co che bi xoa va co che thay the

| Co che cu | Thay bang gi trong mo hinh mot agent |
|---|---|
| `i_hold` + nhanh `if/else` trong `drive_update` | sequence quyet dinh gui **1 hay 2 item** |
| `update_deassert()` goi tu `drive_update` | **item thu hai** voi `is_branch=0`, bay truong fetch giu nguyen |
| `back_to_back` (truong cua item) | `deassert_after` (truong cua sequence) — **CUC TINH NGUOC NHAU**: `back_to_back=0` <-> `deassert_after=1` |
| `park_watchdog` + `update_deassert` khi can item | `park_bus()` + watchdog trong `bpu_driver` — **GIU LAI**, xem muc 4 |
| `bpu_mcsequencer` + `p_sequencer` + `uvm_do_on` | `start()` truc tiep tren `tb.bpu.tx_agent.sequencer` |
| `fork...join` len hai sequencer | goi tuan tu tren mot sequencer |
| Hai `uvm_tlm_analysis_fifo` + hai `get()` lockstep | mot `item_fifo`, mot `get()` |
| Hai `uvm_analysis_export` o `bpu_module_env` | mot `bpu_item_export` |

**Anh xa `deassert_after` da xac dinh bang cach doc ma tung lop**, khong suy dien:

| Lop | `back_to_back_val` cu | `deassert_after` moi | Item moi vong |
|---|:-:|:-:|:-:|
| `bpu_branch_vseq` | 0 (khong caller nao dat lai) | 1 | 2 |
| `bpu_idle_vseq` | 0 (khong he gan) | 1 | 2 |
| `bpu_pipe_helper` | 1 (vo dieu kien) | 0 | 1 |

---

## 4. Bai hoc phan loai: kien truc so voi ban chat tin hieu

Day la ket qua dang ke nhat cua viec chuyen doi, va no khong hien ra tu viec
doc ma.

Bon co che ban dau bi gop lam mot nhom "phai xoa vi thuoc kien truc hai UVC".
Thuc te chung thuoc **hai nhom khac han**:

**Nhom NHIP** — `i_hold`, `update_deassert` goi tu `drive_update`,
`back_to_back`. Chung sinh ra tu viec **tach hai UVC**: hai driver doc lap phai
thoa thuan xem mot lan giai quyet nhanh chiem mot hay hai chu ky. Trong mo hinh
mot agent, cau hoi do bien mat — sequence chi can gui them mot item. Xoa dung.

**Nhom DO BUS** — `park_watchdog`. Co che nay **khong lien quan gi** toi viec
tach UVC. `is_branch` la write-enable **o MUC** cua ca sau bang trong BPU (BTB,
BHT, local PHT, global PHT, choice, GHR). Bat ky driver nao lai mot tin hieu
write-enable o muc, tu mot **dong transaction roi rac**, deu phai co co che tu
ha khi dong can. Mot agent hay hai agent deu vay. Van de nay ton tai o moi kien
truc testbench.

**Hau qua do duoc cua viec xoa nham nhom thu hai.** Sau khi xoa `park_watchdog`,
`is_branch` dung o muc 1 suot **201 chu ky drain**: driver chan o
`get_next_item()`, interface giu nguyen gia tri lai cuoi, DUT cap nhat bang o
moi chu ky con lai. Dau vet chan cua `carry_paths_and_gating_scope_test` lech
**402 dong**:

```
baseline: 2xx 11x0 1x1 6x0 1x1 7x0 1x1 7x0 1x1 7x0 1x1 7x0 1x1 200x0
loi     : 2xx 11x0 1x1 6x0 1x1 7x0 1x1 7x0 1x1 7x0 1x1 7x0 201x1
                                                            ^^^^^^
```

Nam mươi ba chu ky dau khop tuyet doi — moi xung nhanh, moi khoang cach. Chi
duoi lech. **44/44 PASS khong bat duoc loi nay**; chi phep so dau vet chan theo
chu ky bat duoc.

Cach sua giu dung ranh gioi hai nhom: khoi phuc **chuc nang** do bus duoi ten
moi (`park_bus()` trong interface, watchdog trong `bpu_driver`), va **khong**
khoi phuc bat ky thu gi thuoc nhom nhip — khong `i_hold`, khong tham so nhip
trong `drive_bpu_input`, khong bien `held`.

---

## 5. So rui ro hop nhat

| Ma | Mo ta | Trang thai | Bang chung |
|---|---|---|---|
| **R1** | `disable drive_bpu_input` nay ap ca cho duong execute (ban goc `update_reset()` khong co) | **Da dong** | `rst_state_and_async_test` diff dau vet **RONG** (554/554 dong, monitor 565/565), du test nay dung duong reset day dac |
| **R2** | Bon khac biet nho giua hai interface cu, deu chon theo phia predict: kieu cong `input bit`, verbosity `UVM_MEDIUM`, gan `drvstart` bang `<=`, tham so task `input bit` | **Da dong** | Ba cai dau chi anh huong log; cai thu tu an toan vi nguon cua 3 truong execute la `rand bit` nen khong mang X. 44/44 PASS |
| **R3** | Ten transaction doi (`Monitor_BPU_Predict_Item` -> `Monitor_BPU_Item`) | **Da dong** | Chi la nhan ghi song, khong toi chan. Dau vet 7/9 test bit-exact |
| **R4** | Dinh danh cu con trong chu thich | **Con hieu luc, co y** | 3 cho, xem muc 8 |
| **R5** | Watchdog trang bi **vo dieu kien** moi vong (ban goc trang bi co dieu kien theo bien `held`) | **Da dong** | Sau 44 test Xcelium + 44 test Questa: khong test nao co `is_branch` bi ha som. `park_bus` ghi 0 len 0 o cac truong hop ban goc khong trang bi, nen khong doi chan. Miscompares khong tang o bat ky test nao |
| **R6** | Cua so `force` 2ns khong con trum posedge | **Con hieu luc, da chap nhan** | Xem muc 6.1 |
| **R7** | Ba lenh tre `#5ns` -> `#1ns` | **Da dong** | Xem duoi |
| **R8** | +1 chu ky drain o hai test duong `mcseq` | **Con hieu luc, da chap nhan** | Xem muc 6.2 |

**Chi tiet R7.** Thay doi tang test cua toan bo viec chuyen doi gom **ba** lenh
tre, tat ca deu dung ngay sau mot loi goi `.start()`:

| Tep:dong | Trong task | Sua o buoc |
|---|---|---|
| `tests/hyb_btb_tests.sv:70` | `drive_branch()` | lan dau |
| `tests/hyb_btb_tests.sv:95` | `idle_cycles()` | lan dau |
| `tests/global_pht_tests.sv:36` | `drive_branch()` (ban sao thu hai) | lan sau |

Ban sao thu hai bi sot o lan sua dau vi danh sach cho sua duoc sinh bang cach
doc ma va chi ten tep, **khong** bang lenh quet tren cay nguon. Phat hien bang
bang scoreboard 44 test; xac nhan can bang ba bang quet (`grep` moi lenh tre,
moi ban sao `drive_branch`/`idle_cycles`, moi loi goi `.start()` kem hai dong ke
tiep). Ket qua quet: dung ba dinh nghia `drive_branch`/`idle_cycles`, 59 lenh tre
o tang test trong do **chi 3** dung sau `.start()`.

**Ly do can `#1ns`.** Ban hai-UVC ket thuc vseq o **negedge** (vi
`update_deassert` tra ve o negedge), nen `#5ns` dua toi posedge va con nua chu
ky du cho `@(negedge)` ke tiep. Ban mot-agent ket thuc vseq o **posedge**, nen
`#5ns` dua toi **dung ngay negedge** va lenh `@(negedge)` ke tiep lo canh do,
lam moi lan goi tre them mot chu ky. Do duoc: truoc khi sua,
`gshare_index_and_skew_test` va `pshare_index_two_stage_test` lech +2 dong,
`carry_back_to_back_test` +32, `rst_state_and_async_test` +136. Sau khi sua, ca
bon ve **delta = 0**.

---

## 6. Hai sai lech duoc chap nhan

### 6.1 R6 — cua so `force` khong con trum posedge

**Hien tuong.** `gshare_index_and_skew_test` va `pshare_index_two_stage_test`
lech **dung 1 dong** dau vet, va so miscompare giam tu 1 xuong 0.

**Co che.** Hai test nay goi `bd.force_predict_inputs(...)` roi `#2ns` roi doc
bang `chk()`. Ban goc: vseq ket thuc o negedge (t=15), `#5ns` -> t=20 la
posedge, nen cua so force `[20, 22]` **trum mot posedge** va monitor lay mau
chu ky bi force. Ban moi: vseq ket thuc o posedge (t=20), `#1ns` -> t=21, cua so
force `[21, 23]` nam gon giua posedge 20 va negedge 25 — **khong posedge nao roi
vao**.

**Pham vi.** Dung hai test. Tuong quan kin: trong 5 test do dau vet, ba test co
**0** loi goi `force_predict_inputs` deu diff **RONG**; hai test co loi goi deu
lech dung 1 dong. Loi goi `force_predict_inputs` trong
`hyb_fetch_base_test::apply()`/`observe_at()` **khong** thuoc nhom nay vi chung
mo dau bang `@(negedge pvif.clock)` roi moi force, nen cua so luon trum posedge
ke tiep — chung minh bang `rst_state_and_async_test` (goi `apply_idle()` 5 lan,
diff RONG).

**Bang chung vo hai.**

1. `is_branch` mac dinh cua `force_predict_inputs` la `1'b0` (doc tu chu ky ham),
   nen chu ky bi bo lo **khong ghi bang nao**.
2. `chk()` doc bang `uvm_hdl_read` truc tiep tren net, khong qua monitor, khong
   phu thuoc pha clock. `UVM_ERROR = 0` o ca hai ban.
3. **Coverage do rieng tung test**: `gshare` 103/103 bin, delta 0.
   `pshare` 104 -> 107 bin, va tap "base co, moi khong co" la **RONG**.
   Ba bin them duoc (`cp_local_pht_state::WNT`,
   `cx_bht_x_local_pht::<few_ones,WNT>`,
   `cx_local_pht_x_global_pht::<WNT,SNT>`) la vi ban moi lay mau `local_pht` o
   chi muc **that cua luong** thay vi chi muc do `nxpc2` bi force tro toi.
4. **Coverage hop nhat 44 test**: tap bin dat duoc **giong het** baseline theo
   ten, ca hai chieu deu rong.
5. Chieu lech la **it loi hon**: 1 -> 0 miscompare, 215 -> 216 match. Tong so
   phep so sanh **bang nhau** (216/216 va 211/211).
6. Ca hai test tu goi `scoreboard_not_applicable()`, tuc tu khai bao scoreboard
   khong phai checker hop le cho chung (chung ep trang thai noi bo bang
   `force_ghr`/`deposit_*`). Phep kiem that la cac `chk()` doc backdoor.

**Vi sao khong sua duoc.** Dat cua so force trum posedge doi hoi lenh tre sau
`.start()` thoa hai rang buoc mau thuan. Voi posedge tai 20, negedge tai 25,
posedge ke tai 30, vseq ket thuc t=20, goi delta la tre trong `drive_branch`:

- de `@(negedge)` ke tiep bat duoc t=25: `20 + delta < 25`, tuc `delta < 5`
- de `[20+delta, 22+delta]` chua mot posedge: `delta <= 0` hoac `delta >= 8`

Giao cua hai dieu kien chi con `delta <= 0`, ma `delta = 0` la mot **dua canh**
giua tien trinh cua driver va khoi dau vet cung cho `@(posedge clock)`. Tang
`#2ns` cung khong giai quyet: no chi doi chu ky bi chup sang chu ky khac, khong
dua quan sat ve dung chu ky nhu baseline.

**Tieu chi da nhan.** `gshare_index_and_skew_test` va
`pshare_index_two_stage_test` co MISCMP ky vong **0** (baseline 2).

### 6.2 R8 — +1 chu ky trong cua so drain

**Hien tuong.** `btb_rw_all_test` (Total compares 2247 -> 2248) va
`stress_btb_full_test` (3247 -> 3248).

**Co che.** Vseq cuoi ket thuc o **posedge** thay vi **negedge**, nen thoi diem
tha objection dich nua chu ky va cua so drain 2000ns om them dung mot posedge.

**Pham vi.** Dung hai test di duong `mcseq` (`btb_rw_all_mcseq_v2`,
`stress_btb_fill_mcseq`).

**Bang chung vo hai.**

| Phep do | `btb_rw_all_test` | `stress_btb_full_test` |
|---|---|---|
| Phan chung cua dau vet | **2249/2249 dong giong het** | **3249/3249 dong giong het** |
| Bao gom tron so chu ky nhanh | 2048 | 3048 |
| Chu ky lech dau tien | dong 2250 (vuot qua do dai baseline) | dong 3250 |
| Chu ky cuoi co `is_branch=1` | **2049 = 2049** | **3049 = 3049** |
| `is_branch` o chu ky them ra | **0** | **0** |
| `branch_taken` / `branch_offset` | 0 / 0 | 0 / 0 |
| Miscompares | 0 = 0 | 0 = 0 |

Hai phep do doc lap (vi tri dong lech dau tien; chu ky kich thich cuoi) cho
cung ket luan: phan them ra nam **tron trong drain**, sau khi kich thich cuoi
da ket thuc. Drain la khoang thoi gian sau khi objection cuoi duoc tha, ton tai
de he thong lang. Mot chu ky trong them trong do voi `is_branch = 0` khong ghi
bang nao.

**Vi sao khong sua duoc bang lenh tre.** Ba loi goi `.start()` cua duong `mcseq`
(`hyb_btb_tests.sv:393`, `stress_tests.sv:25`, `stress_tests.sv:31`) **khong co
lenh tre nao theo sau** — xac nhan bang lenh quet `grep -A2` tren moi loi goi
`.start()` o tang test va vseq. Khong co gi de chinh.

**Tieu chi da nhan.** Hai test nay co Total compares +1 so baseline.

---

## 7. Phuong phap kiem chung

Cau hoi "lam sao biet hanh vi khong doi" duoc tra loi bang sau phep do doc lap.

**1. Dau vet chan theo chu ky (`BPU_PIN_TRACE`).** Mot khoi `always @(posedge
clock)` in 13 tin hieu tai moi posedge sau khi `rst_n` len, ra tep. Khoi nay chi
doc cong cua instance `dut` nen **van ban giong het nhau o ca hai ban** — do la
dieu kien de phep so co nghia. Da do tren **9 test**. Tinh tai lap da kiem: chay
lai cung mot ban cho tep giong het (Xcelium dung seed co dinh).

**2. Ba cot scoreboard tren ca 44 test.** `Total compares`, `Matches`,
`Miscompares` trich tu `report_phase`, doi chieu base-moi tung dong.

**3. So item monitor.** `"BPU Monitor Collected N Items"`, kiem cheo doc lap voi
dau vet: quan he `N = so dong dau vet - 2` dung o moi test da do.

**4. Tap bin functional coverage theo TEN.** Trich `(coverpoint hoac cross)::bin`
kem trang thai, so hai chieu bang `comm`.

**5. Code coverage tung metric tren 4 design unit RTL.**

**6. Mot test phai FATAL y het.** `local_pht_counter_and_init_test` phai fatal
tren Questa voi `vsim-16133` tren
`bpu_hw_top.dut.u_bpu_reg.local_bht[64]` — day la phep kiem **nguoc** duy nhat.
Neu no bong PASS thi nghia la mot loi goi `force` khong con cham dung cho.

### Phep nao bat duoc loi nao

Day la phan quan trong nhat cua muc nay: moi loi that su xay ra deu bi bat boi
**dung mot** phep do, va cac phep do khac im lang.

| Loi | Phep bat duoc | Phep **khong** bat duoc |
|---|---|---|
| Xoa nham `park_watchdog` (`is_branch` dung muc 1 suot 201 chu ky drain) | **Dau vet chan** (402 dong lech) | 44/44 van PASS |
| Lech pha nua chu ky sau khi doi giao thuc (`#5ns`) | **Dau vet chan** (delta +2/+32/+136) | 44/44 van PASS; MISCMP khong doi |
| Ban sao `#5ns` thu hai bi sot trong `global_pht_tests.sv` | **Ba cot scoreboard tren 44 test** (Total +2 o hai test) | Dau vet 5 test khong di qua duong do; 44/44 van PASS; MISCMP khong doi |
| Hoan vi bin coverage (neu co) | **Tap bin theo ten, hai chieu** | Con so tong 302 khong bat duoc |
| Duong `force` bi che | **Test phai fatal** | Moi phep do xuoi khac |

Bai hoc: **mot phep do chi co gia tri tren duong ma no thuc su di qua.** Dau vet
5 test khong phu duong `global_pht_base_test`, nen no khong the phu dinh gia
thuyet ve duong do; phai co phep quet tren ca 44 test moi phat hien.

---

## 8. Dinh danh cu con trong chu thich

Tieu chi: trong **ma thuc thi**, cac dinh danh cu phai bang 0. Trong **chu
thich**, cho phep nhung phai liet ke.

| Tep:dong | Loai | Noi dung | Ly do giu |
|---|---|---|---|
| `tb/bpu_drive_vseqs.sv:92` | chu thich | `// Ban goc KHONG gan back_to_back_val nen no giu mac dinh 0...` | Giai thich vi sao `bpu_idle_vseq` phai phat 2 item moi vong — quyet dinh kho nhat cua tang kich thich |
| `tb/bpu_drive_vseqs.sv:128` | chu thich | `// dung nhu update_deassert cu gan 0 len tin hieu von da 0.` | Giai thich vi sao item thu hai giong het item thu nhat |
| `bpu_agent/bpu_driver.sv:66` | **ma thuc thi** | `begin : park_watchdog` | **Ten nhan khoi `fork`, co y giu**: day la co che Nhom 2 duoc tai dinh nghia (muc 4), khong phai tan du |

Trong ma thuc thi: `i_hold`, `update_deassert`, `back_to_back_val`,
`mcsequencer`, `p_sequencer`, `bpu_base_mcseq` deu bang **0**.

`bpu_predict`/`bpu_update` con **12 cho**, tat ca la chu thich ghi nguon goc hop
nhat, cong hai macro guard `BPU_PREDICT_IF_STRICT_FLUSH_IN` /
`BPU_UPDATE_IF_NO_ASSERTS` va cac ID thong bao `"BPU_PREDICT_IF"` /
`"BPU_UPDATE_IF"` — hai thu sau **bat buoc giu nguyen** de van ban log cua 7
assertion khong doi.

`bpu_predictor` la ten module RTL, khong lien quan.

Ngoai le da chot: `back_to_back` con trong ten test `carry_back_to_back_test`
(muc 14.4 cua testplan) va trong `testlist_44.txt`. Doi ten se doi danh sach
test.

---

## 9. Danh gia thiet ke

**Cai duoc.**

- Giam **413 dong nguon** (12985 -> 12572). Ha tang UVC giam tu 1932 dong (hai
  UVC + virtual sequencer + thu vien mcseq) xuong 1473 dong (mot agent).
- Bo mot tang truu tuong: khong con virtual sequencer, `p_sequencer`,
  `uvm_do_on`, va `fork...join` o moi kich thich mot chu ky.
- Mo hinh tham chieu don gian han: mot `get()` thay hai lenh lockstep. Khong con
  kha nang hai luong item lech nhip — mot lop loi bi loai bo tan goc.
- Tang kiem tra bot mot `uvm_analysis_export` va mot FIFO.

**Cai mat.**

- Khong con vi du kien truc nhieu-UVC + virtual sequencer trong dU an. Neu tai
  lieu nay phuc vu muc dich giang day thi day la mot mat mat that.
- `bpu_seqs.sv` (546 dong) va ba sequence quet trong `bpu_drive_seqs.sv` la ma
  chet — khong test nao goi. Chung duoc giu de khong mat tinh nang cua UVC, va
  moi lop deu co dong `// MA CHET` ghi ro. Trong ban hai UVC chung cung da la ma
  chet, nen day khong phai hoi quy, nhung viec gop lam chung lo ro han.
- Hai bien `predict_if_path` / `update_if_path` trong `bpu_backdoor.sv` nay tro
  vao cung mot interface. Co y giu hai bien de diff nho nhat co the; viec hop
  nhat chung la don dep, chua lam.

**Truong hop nen tach lai thanh hai agent.**

- Neu duong cap nhat co giao thuc bat tay rieng (`valid`/`ready`) thay vi la
  mot tin hieu write-enable o muc. Khi do hai phia co **nhip doc lap** va viec
  ep chung vao mot item mot chu ky se mat thong tin.
- Neu hai phia chay o **hai mien clock khac nhau**. Mot agent chi lay mau duoc
  mot canh clock.
- Neu can cau hinh doc lap: mot phia `UVM_ACTIVE`, phia kia `UVM_PASSIVE`.
- Neu dinh tai su dung rieng mot phia cho mot DUT khac.

Trong BPU hien tai khong dieu nao dung: ca 10 chan vao nam chung mot mien clock,
lay mau chung mot canh, va `is_branch` la write-enable o muc chu khong phai mot
giao thuc bat tay. Do la ly do viec gop la dung cho thiet ke nay.

---

## 10. Trang thai cuoi

| Tieu chi | Ket qua |
|---|:-:|
| Xcelium 44/44 PASS | dat |
| 40/44 dong khop tuyet doi ba cot scoreboard | dat |
| Dung 4 dong lech duoc phep (R6 x2, R8 x2) | dat |
| MISCMP `carry_paths_and_gating_scope_test` 11 = 11 | dat |
| Functional coverage 302/302, tap bin giong het theo ten | dat |
| Code coverage 100% moi metric tren 4 design unit | dat |
| `local_pht_counter_and_init_test` fatal y het, duong dan HDL khong doi | dat |
| `diff -r bpu_uvm_3/rtl bpu_uvm_4/rtl` rong | dat |
| `bpu_predict/`, `bpu_update/`, `bpu_mcsequencer.sv`, `bpu_mcseqs_lib.sv` da xoa | dat |
| Ma thuc thi khong con dinh danh co che cu | dat |
