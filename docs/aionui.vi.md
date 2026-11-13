# Làm việc qua AionUi (máy và điện thoại)

> Quy trình hằng ngày khi điều khiển Claude Code bằng AionUi thay vì terminal, kể cả từ điện
> thoại. Vòng làm một ticket và các lệnh `/sdw:*`: [du-an-moi.vi.md](du-an-moi.vi.md).

## AionUi chạy Claude thế nào

AionUi không có agent riêng: nó chạy chính CLI `claude` (chế độ `--print`, stream-json) với
`~/.claude/settings.json` của bạn. Vì vậy sdw, mọi plugin và skill đã cài ở cấp user đều có mặt,
cùng hook, gate và luật deny.

- Trang **Skills** của AionUi chỉ liệt kê skill của AionUi. **Đừng import** skill Claude vào đó:
  chúng bị nạp hai lần, và skill sdw tách khỏi plugin thì thiếu bin và hook.
- Gõ lệnh như ở terminal: `/sdw:plan #3`. Menu gợi ý của AionUi có thể không liệt kê chúng.

## Project và Conversation

| Mục ở sidebar | Thư mục chạy | Dùng cho |
|---|---|---|
| **Projects** | thư mục bạn chọn khi tạo chat | **một Project = một repo**; mỗi việc một chat trong đó |
| **Conversations** | thư mục tạm riêng (`~/.aionui/conversations/.../claude-temp-…`) | câu hỏi không gắn repo; sdw không thấy `.sdw/` |
| **Teams** | thư mục của trưởng nhóm, **dùng chung** cho mọi thành viên | review, QA, tìm hiểu; không code song song |

- **Không** tạo Project ở thư mục cha chứa nhiều repo: sdw coi đó là workspace nhiều repo và
  onboard tất cả.
- Làm song song: `/sdw:plan` tạo worktree `../<repo>-<slug>` nằm ngoài repo, nên tạo một Project
  riêng cho thư mục worktree đó; archive sau `/sdw:wrap`.
- Đặt tên chat theo việc: `sync`, `#12 export csv`, `review PR 34`. Chat dài, compact nhiều lần →
  mở chat mới trong cùng Project; trạng thái nằm ở `.sdw/work/<branch>/`, không nằm trong chat.

## Thiết lập một lần

1. **Mỗi repo:** New Chat → agent **Claude Code** → chọn thư mục repo → quyền **mặc định** → gửi
   `/sdw:onboard`. Trả lời câu hỏi của nó trong chat.
2. **Quyền:** repo khách luôn để mặc định (duyệt từng thao tác). `bypassPermissions` chỉ cho repo
   cá nhân; đừng dựa vào luật "hỏi trước `git push`" ở chế độ bypass.
3. **Team:** thành viên dùng chung một thư mục (`workspace_mode: shared`) và chỉ có MCP của AionUi
   (`--strict-mcp-config`: không Figma, không Atlassian). Thành viên không phải Claude (Gemini,
   Antigravity…) không có sdw và gửi code ra nhà cung cấp khác: không dùng với repo khách chưa cho
   phép. Repo mà merge vào main là deploy: không dùng Team.
4. **Model theo việc:** sync, báo cáo, việc lặt vặt → model rẻ; plan, debug khó, review → model mạnh.

## Một ngày

| Lúc | Chat | Làm |
|---|---|---|
| Sáng | `sync` (model rẻ) | `/sdw:sync`; branch đã merge → `/sdw:wrap` |
| Nhận việc | chat mới `#N …` | `/sdw:plan #N`; đọc AC và lane trước khi đồng ý |
| Làm | cùng chat | `/sdw:debug` hoặc `/sdw:test`, code theo slice; duyệt quyền khi được hỏi |
| Kiểm | cùng chat | `/sdw:qa` → `/sdw:review` |
| Đẩy | cùng chat | `/sdw:commit` → `/sdw:ship`; merge khi CI xanh và bạn đồng ý → `/sdw:wrap` |
| Cuối ngày | `sync` | `/sdw:daily-report`; việc dở commit WIP lên branch của nó |

Tối đa 2–3 việc song song: review không song song được.

**Điện thoại:** duyệt quyền, trả lời câu hỏi của skill, giao việc ngắn ("làm slice 2"), đọc
verdict QA. **Ngồi máy:** đọc diff, xem giao diện, quyết định merge, mọi việc nhạy cảm trên repo
khách.

## Điều khiển từ điện thoại

1. AionUi → **Settings → Remote**: bật WebUI, **tắt "Allow remote access"** (bật nó là mở cổng
   25808 cho cả mạng wifi đang ngồi). Đặt mật khẩu mạnh.
2. Mac: mở Tailscale, đăng nhập (Connected), rồi:
   ```bash
   tailscale serve --bg 25808      # in ra https://<máy>.<tailnet>.ts.net, chỉ máy trong tailnet vào được
   tailscale serve status          # kiểm tra
   tailscale serve reset           # tắt chia sẻ
   ```
   Lần đầu Tailscale có thể đòi bật HTTPS/MagicDNS cho tailnet: làm theo link nó in.
3. Điện thoại: cài Tailscale, cùng tài khoản → mở URL trên bằng Safari → đăng nhập `admin` →
   **Thêm vào màn hình chính**.
4. Mac phải thức: cắm sạc, **Cài đặt → Pin → Tuỳ chọn → ngăn tự ngủ khi màn hình tắt**, hoặc
   `caffeinate -dimsu` trong một tab terminal.
5. Thử bằng 4G (tắt wifi) trước khi cần thật.

Ai đăng nhập được WebUI là chạy được lệnh trên máy bạn. Không dùng chế độ deploy lên server, không
mở port ra Internet, tắt WebUI khi không cần.

## Cron

Scheduled Tasks của AionUi chạy được `/sdw:sync` mỗi sáng, nhưng mỗi lần chạy tốn quota. Chỉ đặt
việc bạn thật sự đọc kết quả.

## Khi có gì lạ

| Triệu chứng | Nguyên nhân thường gặp |
|---|---|
| sdw không biết dự án, không có gate | chat nằm ở Conversations (thư mục tạm), không phải trong Project |
| Plugin mới cài không có | chat đã mở trước khi cài: tạo chat mới |
| Công cụ LSP C# báo "server is starting" | Roslyn đang nạp solution, chờ vài giây rồi thử lại |
| Hai agent sửa đè nhau | cùng một thư mục (Team hoặc hai chat cùng Project): dùng worktree |
| `gh` 404 hoặc thiếu quyền | sai tài khoản đang active: `gh auth status`, `gh auth switch -u <user>` |
