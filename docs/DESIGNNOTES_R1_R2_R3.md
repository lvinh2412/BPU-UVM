# DesignNotes R1, R2, R3 — Trạng thái xác minh

*Đóng ở Giai đoạn 6, lô 2. Mọi số liệu trong tài liệu này đều là số đo thực,
lấy từ log của các mục kiểm chứng tương ứng trên cả xrun và QuestaSim.*

Ba quan sát R1–R3 xuất phát từ việc đọc RTL của module BPU. Kiểm chứng ở **mức
module** trả lời được câu hỏi *"hiện tượng có xảy ra không, trong điều kiện
nào"*, nhưng **không** trả lời được câu hỏi *"hệ quả ở lõi tích hợp là gì"* —
vì môi trường kiểm chứng này chỉ có BPU, không chạy lệnh và không có tầng
fetch/decode thật của lõi. Mỗi mục dưới đây vì vậy tách làm ba phần: đã xác
minh được gì, còn lại gì, và phát biểu thế nào nếu không tiếp cận được lõi.

---

## R1 — Tầng fetch chuyển hướng mà không kiểm opcode; BTB không có trường tag

### Đã xác minh được ở mức module

Ba mục độc lập tái hiện được, ở ba điều kiện khác nhau:

| Mục | Điều kiện | Kết quả đo |
|---|---|---|
| **8.2** `predict_index_alignment` | Năm địa chỉ cách nhau bội số 4 KB (`0x100`, `0x1100`, `0x2100`, `0x3100`, `0xFFFFF100`) đưa vào `nxpc2` | Cả năm cho **cùng** `btb_valid=1`, `btb_target=0x140`, `predT=1` |
| **9.1** `precompute_gating_and_opcode_scope` phần (c) | Tầng decode bị chặn, chỉ còn tầng fetch | Tầng fetch vẫn phát chuyển hướng |
| **15.5** `pattern_btb_aliasing` (thêm ở Giai đoạn 5) | Địa chỉ `0x1100` với `fetch_opcode=ADDI`, `is_branch=0` — **không phải lệnh rẽ** — trùng chỉ mục BTB với nhánh `0x100` đã huấn luyện | Tiền đề đạt **20/20**; tầng fetch vẫn thắng MUX và phát chuyển hướng **20/20** |

Cơ chế đã xác định trong RTL: `bpu_reg.v:52,66,70` lưu BTB không kèm tag, và cả
ba chỉ mục dự đoán (`local_bht[nxpc2]`, `nxpc2 ^ ghr`, `choice[nxpc2]`) đều chỉ
lấy `pc[11:2]`. `fetch_opcode` chỉ đến ở tầng DECODE (`bpu_ctrl.v:41`), nên tầng
fetch về nguyên tắc không thể biết địa chỉ nó đang tra có phải lệnh rẽ hay không.

**Kết luận mức module: R1 tái hiện được, có định lượng, và nguyên nhân là hệ quả
cấu trúc của thiết kế — không phải lỗi cài đặt.**

### Còn lại cần đối chiếu với lõi

Mức module chỉ chứng minh **BPU phát ra** một chuyển hướng sai. Nó không trả lời
được:

1. Lõi có **dùng** `bpu_nxpc2` đó không, hay còn một tầng lọc nào nữa (ví dụ
   kiểm hợp lệ ở tầng fetch của lõi) mà tài liệu module không thấy.
2. Chi phí thực tế mỗi lần chuyển hướng nhầm là bao nhiêu chu kỳ ở lõi.
3. Tần suất thực tế: phụ thuộc bố cục bộ nhớ của chương trình thật, mà môi
   trường này không mô phỏng được.

### Nếu không tiếp cận được lõi

> BTB của khối BPU không lưu trường tag và tầng fetch tra bảng thuần theo
> `pc[11:2]`. Kiểm chứng mức module xác nhận hai địa chỉ cách nhau bội số 4 KB
> được coi là một, và một địa chỉ **không phải lệnh rẽ** trùng chỉ mục với một
> nhánh đã nằm trong BTB vẫn khiến BPU phát chuyển hướng (đo được 20/20 lần).
> Hệ quả ở mức lõi — lõi có lọc thêm hay không, và chi phí mỗi lần — **chưa được
> kiểm chứng** trong phạm vi đề tài. Hướng phát triển: thêm trường tag hoặc một
> bit hợp lệ theo opcode cho BTB, và đo lại ở môi trường lõi tích hợp.

---

## R2 — Carry-down không bị xoá khi có flush

### Đã xác minh được ở mức module

Mục **14.3** `carry_across_flush` đo ba pha:

| Pha | Điều kiện | Kết quả đo |
|---|---|---|
| A | `flush_in=2` tại F+1 | Tại F+2 vẫn có `predicted_taken=1`, `pred_was_hit=1` — đường ống **không** bị xoá |
| B | Lệnh đã bị xoá (`is_branch=0` tại execute) | `bpu_flush=0`, không có hiệu chỉnh |
| C | Nhánh kế tiếp | `predicted_taken=0` — dùng đúng quyết định fetch của **chính nó** |

Đọc từ RTL khớp với số đo: `bpu_ctrl.v:59-76` chỉ có `rst_n` xoá tám thanh ghi
carry-down, còn `halt` chỉ đóng băng; không có đường nào cho `flush_in` xoá
chúng. Và `bpu_ctrl.v:87,92` ép cả `bpu_flush` lẫn `corr_valid` về 0 khi
`is_branch=0`.

**Kết luận mức module: hệ quả xấu của R2 KHÔNG tái hiện được.** Quyết định còn
sót lại là vô hại, vì đường ống mang tính **vị trí**: quyết định của mỗi lệnh
tới execute đúng hai chu kỳ sau khi nó ở fetch, rồi rời đi.

### Còn lại cần đối chiếu với lõi

Điều kiện an toàn ở trên dựa trên một giả định: **một lệnh đã bị xoá thì không
bao giờ tới execute với `is_branch=1`**. Giả định này nằm ngoài BPU — nó là hợp
đồng của lõi. Nếu lõi có một đường nào để lệnh đã bị flush vẫn tới tầng execute
và khai báo `is_branch=1`, BPU sẽ so nó với quyết định carry-down của chính vị
trí đó và có thể phát hiệu chỉnh giả. **BPU không có cách nào biết một lệnh đã
bị xoá.**

### Nếu không tiếp cận được lõi

> Tám thanh ghi carry-down chỉ bị xoá bởi `rst_n`, không bởi `flush_in`. Kiểm
> chứng mức module cho thấy điều này **không** gây hậu quả trong phạm vi khối
> BPU: khi lệnh đã bị xoá tới execute với `is_branch=0`, cả `bpu_flush` lẫn
> `corr_valid` đều bị ép về 0. Tính đúng đắn vì vậy phụ thuộc vào một **hợp đồng
> với lõi**: lệnh đã bị flush không được tới tầng execute với `is_branch=1`.
> Hợp đồng này **chưa được kiểm chứng** trong phạm vi đề tài. Hướng phát triển:
> hoặc kiểm chứng hợp đồng ở môi trường lõi tích hợp, hoặc bổ sung đường xoá
> carry-down theo `flush_in` để khối BPU tự bảo đảm, không phải dựa vào lõi.

---

## R3 — `bpu_flush=1` đồng thời `corr_valid=1`

### Đã xác minh được ở mức module

Mục **12.2** `corr_flush_decoupling` pha B tái hiện được tổ hợp này, với điều
kiện đã ghi rõ:

- tại F: `btb_valid_nxpc2 = 0` (địa chỉ chưa từng vào BTB)
- tại F+1: tầng dự phòng **bị chặn** (dùng opcode khác BCC; dùng
  `fetch_ready=0` hoặc `btb_valid_nxpc=1` do trùng chỉ mục đều ra cùng kết quả)
- tại F+2: `is_branch=1`, `branch_taken=1`

Kết quả đo:

```
pred_was_hit    = 0
predicted_taken = 0
bpu_flush       = 1      <- quy tắc !pred_was_hit -> taken ? 1 : 2
corr_valid      = 1      <- mispredict vì predicted_taken != branch_taken
corr_nxpc2      = 0x554  (= pc + branch_offset, đúng kỳ vọng)
```

**Kết luận mức module: R3 tái hiện được, điều kiện đã xác định đầy đủ.**

### Còn lại cần đối chiếu với lõi

Vấn đề nằm ở **ý nghĩa** của `bpu_flush=1`, không ở giá trị của nó.
`bpu_flush=1` vốn dựa trên giả định "tầng dự phòng ĐÃ chuyển hướng đúng ở F+1",
nên chỉ cần một bong bóng. Nhưng trong kịch bản này tầng dự phòng **không** kích
hoạt, nên đường ống đã đi tuần tự — và việc chuyển hướng tại execute thường cần
**hai** bong bóng chứ không phải một.

Câu hỏi mở: một bong bóng có đủ để lõi áp dụng được `bpu_nxpc2` hay không? Điều
đó phụ thuộc cách lõi diễn giải `bpu_flush` và độ sâu thật của tầng fetch — cả
hai đều ngoài phạm vi kiểm chứng mức module.

### Nếu không tiếp cận được lõi

> Tồn tại một tổ hợp trong đó BPU phát `bpu_flush=1` (một bong bóng) đồng thời
> `corr_valid=1` với địa chỉ hiệu chỉnh đúng. Điều kiện tái hiện đã được xác
> định đầy đủ và kiểm chứng ở mức module. Rủi ro là số bong bóng do
> `bpu_flush=1` báo có thể **không đủ** cho lõi áp dụng địa chỉ hiệu chỉnh,
> vì trong kịch bản này tầng dự phòng không kích hoạt nên đường ống chưa được
> chuyển hướng trước. Việc một bong bóng có đủ hay không **chưa được kiểm
> chứng** trong phạm vi đề tài — nó phụ thuộc cách lõi diễn giải `bpu_flush`.
> Hướng phát triển: đối chiếu với tầng fetch của lõi, hoặc tách `bpu_flush`
> thành hai tín hiệu độc lập (số bong bóng cần xoá, và có hiệu chỉnh hay không)
> để loại bỏ hoàn toàn sự mơ hồ này.

---

## Tổng hợp

| | Tái hiện ở mức module | Bằng chứng | Phần còn lại |
|---|---|---|---|
| **R1** | **Có**, ba mục độc lập | 8.2 (5/5 địa chỉ), 9.1(c), 15.5 (20/20) | Lõi có lọc thêm không; chi phí và tần suất thực tế |
| **R2** | **Không** tái hiện được hệ quả xấu | 14.3 ba pha | Hợp đồng "lệnh đã xoá không tới execute với is_branch=1" |
| **R3** | **Có**, điều kiện đã xác định | 12.2 pha B | Một bong bóng có đủ để lõi áp dụng hiệu chỉnh không |

Cả ba đều có phần phụ thuộc RTL lõi mà kiểm chứng mức module không trả lời được.
Không mục nào ở đây kết luận rằng thiết kế sai; các phát biểu chỉ đi đúng tới
ranh giới bằng chứng đang có.
