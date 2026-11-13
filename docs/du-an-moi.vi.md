# Vào dự án mới — từ ngày đầu tới ngày cuối

> Runbook cho dev fullstack join repo của team/khách hàng với plugin `sdw`. Đọc kỹ một lần,
> sau đó chỉ cần nhìn bảng. Tham chiếu tiếng Anh: [README](../README.md).

## 0. Một lần trên máy

```bash
cd <thư mục repo workflow này>
./bootstrap.sh --dry-run                       # xem trước; dừng ở bước kiểm tra đầu tiên lỗi
./bootstrap.sh --verify-skill --with-qa-tools --security-skill
```

Chi tiết từng bước: [README#install](../README.md#install-once-per-machine). Cần một tag `vX.Y.Z`
trong clone này (`git fetch --tags`); bootstrap cài tag mới nhất, không phải thư mục đang sửa.

- `~/.claude/CLAUDE.md` chỉ được tạo nếu chưa có: thói quen của bạn (ngôn ngữ, không
  attribution, giờ là ước lượng). Không bao giờ ghi tên khách hàng, URL, token vào đó.
- `--verify-skill`: Claude tự chạy gate + kiểm tra test bị làm yếu trước mỗi commit, kể cả
  khi commit qua `/commit` riêng của team.
- `--security-skill`: skill `security-audit` của Cloudflare, ghim theo commit đã đọc; xem bảng "Skill nào
  lúc nào".
- Máy còn bản v1 (`install.sh`) trong dự án cũ: `./bootstrap.sh --migrate <dir> --dry-run`.

## 1. Ngày đầu

```bash
cd ~/work/<repo>          # hoặc thư mục cha (không phải git) chứa nhiều repo
claude
```

Gõ **`/sdw:onboard`**. Nó sẽ:

1. đọc `CLAUDE.md`, `AGENTS.md`, CONTRIBUTING, CI của team — luật của team thắng;
2. ghi lại các skill riêng của repo (`/commit`, `/push`, …) để `/sdw:*` nhường;
3. kiểm tra Node/.NET/Python so với repo pin, ghi cách sửa vào `.sdw/env.sh` (mỗi session
   sau tự `source`);
4. dựng stack local, kiểm tra port, chạy test một lần trên base → `.sdw/state/baseline.md`
   (lỗi có sẵn được ghi là có sẵn);
5. dựng gate **fast** (typecheck + lint) và **full** (mọi bước CI chạy được ở local), chạy thử
   trên base; gate đỏ sẵn thì thu hẹp hoặc lưu baseline lỗi → `.sdw/gates`;
6. tìm contract/spec, auth, migration, tracker, design, và **ai phụ trách mảng nào** (PO, designer,
   BE lead, DevOps, QA…) → `.sdw/people.md` (chỉ tên và handle Slack, không email/số điện thoại);
7. chuẩn bị cho QA: role, hai user test mỗi role, công thức login → `.sdw/run.md`.

**Không có gì bị commit.** Mọi thứ nằm trong `.sdw/`, được ẩn qua `.git/info/exclude`.
Kiểm tra: `git status` phải sạch. Token/mật khẩu nằm trong Keychain; onboard in sẵn lệnh:

```bash
security add-generic-password -U -s '<service>' -a '<account>' -w    # nó hỏi giá trị, không lộ lên màn hình
```

Đọc lại `.sdw/project.md`, sửa chỗ sai, hỏi team tối đa 5 câu onboard đưa ra.

## 2. Mỗi ngày

| Khi | Gõ |
|---|---|
| Đầu ngày | `/sdw:sync` — commit mới, PR, contract đổi gì, ticket, design; branch đã merge thì nhắc `/sdw:wrap` |
| Nhận ticket | `/sdw:plan ABC-123` — chọn lane, AC ghi ra file, tạo branch hoặc worktree; tự chạy `/sdw:clarify` |
| Spec/design mơ hồ | `/sdw:clarify <ticket \| spec \| link design>` — soi lỗ hổng, mâu thuẫn, state thiếu, UX; câu hỏi chia theo người, có sẵn tin nhắn Slack (tiếng Anh) để bạn tự gửi |
| Có bug | `/sdw:debug <triệu chứng hoặc BUG-nn>` |
| Viết test | `/sdw:test` — đúng tầng, chứng minh test đỏ trên base |
| Đang code UI | `/sdw:ui-polish <route> <selector>` — state của từng control, motion, reduced motion, layout shift, INP, các width |
| Code xong | `/sdw:qa` (agent QA độc lập) · `/sdw:verify-ui <route> <frame>` nếu có design |
| Trước commit | `/sdw:review` → `/sdw:commit` |
| Mở PR | `/sdw:ship` — chỉ merge khi CI xanh **và** bạn đồng ý |
| Review PR người khác | `/sdw:review-pr 123` |
| Sau khi merge | `/sdw:wrap` |
| Cuối ngày | `/sdw:daily-report` · `/sdw:logwork` nếu team cần |

Lane do `/sdw:plan` chọn (rủi ro thắng kích thước):

| Lane | Khi nào | Vòng lặp |
|---|---|---|
| TRIVIAL | không đổi hành vi | sửa → `/sdw:qa quick` nếu nhìn thấy được → `/sdw:commit` |
| STANDARD | mặc định, kể cả ticket fullstack | code → `/sdw:qa` → `/sdw:review` → `/sdw:commit` → `/sdw:ship` |
| RISKY | authz/role, migration, xoá dữ liệu, đổi contract, tiền, UI dùng chung | (`/sdw:plan` đã chạy QA design) `/sdw:test from-qa` → code → `/sdw:qa` → review |
| BUG | ticket loại Bug | `/sdw:debug` → `/sdw:qa` |

**Đọc verdict QA** (`.sdw/work/<branch>/qa-report.md`): `READY` — đủ điều kiện;
`READY WITH KNOWN ISSUES` — chỉ còn lỗi S3/S4 hoặc case P2 chưa chạy (đã liệt kê);
`NOT READY` — còn S1/S2, AC chưa PASS, hoặc thiếu user/trình duyệt (case thành BLOCKED, không
bao giờ thành PASS). Bug FAIL → `/sdw:debug BUG-nn` → `/sdw:qa retest`.

`/sdw:plan` tự chạy QA design; chỉ gõ `/sdw:qa design` khi mở session mới trong worktree. Một skill
cần skill khác có side effect (commit, ship, wrap…) sẽ **in lệnh để bạn gõ**, không tự chạy.

### Một ngày mẫu

**Sáng (~15 phút)**

1. Mở session ở thư mục repo (checkout chính, không code ở đây) → `/sdw:sync`. Đọc phần "đổi gì":
   contract, migration, design. Base đổi thì sync tự đo lại baseline. Branch nào đã merge thì
   `/sdw:wrap` từng cái.
2. Chọn tối đa 2–3 ticket cho hôm nay; ticket RISKY làm lúc đầu óc còn tỉnh.

**Mỗi ticket — một session riêng**

3. `/sdw:plan <ticket>`: đọc lại AC và lane trước khi đồng ý. Câu hỏi nằm ở
   `.sdw/work/<branch>/questions.md`, mỗi người một tin nhắn: đọc lại, sửa giọng, **tự** dán vào
   Slack (thread của ticket hoặc channel dự án). Có trả lời → dán lại cho Claude, nó sửa AC/spec
   trước rồi mới code. Câu chặn việc mà chưa có trả lời → làm slice khác, đừng đoán. Làm song song → nhận worktree, mở
   session mới **trong thư mục worktree**.
4. Code theo từng slice của plan. Slice có UI → `/sdw:ui-polish` trước khi coi là xong. Bug → `/sdw:debug`. Test → `/sdw:test` (test phải đỏ trên base
   trước khi xanh). Hỏi API thư viện → bảo Claude tra tài liệu chính thức (với .NET: plugin
   `microsoft-docs`) thay vì đoán.
5. Gate fast chạy khi Claude dừng (hook `stop-gate`). Đỏ thì sửa ngay, đừng gom lại.
6. Xong code → `/sdw:qa`. Màn hình có design → `/sdw:verify-ui <route> <frame>`; không có design →
   bảo Claude review UI bằng skill `web-design-guidelines`.
7. `/sdw:review` → sửa → `/sdw:commit` → `/sdw:ship` → merge khi CI xanh **và** bạn đồng ý →
   `/sdw:wrap`.
8. Session dài, nhiều lần compact → mở session mới. Trạng thái nằm ở `.sdw/work/<branch>/`, không
   nằm trong lịch sử chat.

**Cuối ngày (~10 phút)**

9. `/sdw:daily-report` (giờ là ước lượng, tối đa 8h/ngày) · `/sdw:logwork` nếu team cần.
10. Việc dở: commit WIP lên branch của nó (không `git stash`), ghi một dòng "mai làm gì" vào
    `.sdw/work/<branch>/`. Dừng dev server bạn đã bật. Tắt truy cập từ xa nếu không cần.

### Skill nào lúc nào

| Việc | Skill (tự kích hoạt trừ khi ghi khác) |
|---|---|
| Code C#, refactor, MSBuild | `dotnet:*` (Microsoft), kèm LSP C# (cần .NET 10 SDK) |
| EF Core chậm, test .NET | `dotnet-data:*`, `dotnet-test:*` (chỉ bật trong repo .NET) |
| API .NET/Azure/SignalR | `microsoft-docs` — tra Microsoft Learn |
| React/Next.js | `vercel-react-best-practices` |
| Review UI, accessibility | `web-design-guidelines` |
| Motion, micro-interaction, state của control | `/sdw:ui-polish` (đo bằng `sdw-ui-shot --motion/--vitals`) |
| Review animation kỹ (tuỳ chọn) | `emilkowalski/skills` (MIT): `review-animations` chỉ khi gọi tên; `animation-performance` tự kích hoạt khi animation giật. Nó nhắc skill `animate` (không cài): luật timing/easing đã có trong `/sdw:ui-polish` |
| Dashboard realtime (SignalR, socket) | `/sdw:ui-polish` mục "Live data": không animate mỗi lần data về, `tabular-nums`, chart append không transition, state reconnecting/stale/offline |
| Phản biện spec, requirement, design | `/sdw:clarify` · audit usability sâu hơn: `ux-heuristics` |
| LCP/INP/CLS thật | Chrome DevTools MCP, trace trên production build ([mcp.md](mcp.md#chrome-devtools)) · skill `core-web-vitals` (`addyosmani/web-quality-skills`) |
| Audit usability | `ux-heuristics` (`wondelai/skills`): Nielsen, Krug, dark pattern |
| Soi bảo mật diff của PR | `/security-review` (có sẵn trong Claude Code) |
| Audit bảo mật toàn repo | `security-audit` — gõ rõ "security audit this codebase, quick profile, budget 15 agents"; lúc mới onboard và trước release lớn. Báo cáo ở `~/security-audit-skill/<repo>/`: không commit, không dán ra ngoài, xoá khi offboard |
| Trang mới **không có** design | `design-taste-frontend` — repo đã có design system thì bám component của dự án |
| Style riêng | `minimalist-ui`, `high-end-visual-design` — chỉ khi gọi tên |

Mỗi skill tự kích hoạt tốn context mọi lượt. Plugin nặng thì tắt ở cấp user và bật theo repo:
`claude plugin enable <plugin> --scope local` trong thư mục repo (ghi vào
`.claude/settings.local.json`, không commit). Ví dụ `dotnet-test` thêm ~5.400 token mỗi session.
LSP TypeScript cần `npm i -g typescript-language-server typescript@6`: TypeScript 7 (bản Homebrew)
không còn `tsserver.js`. Thêm skill mới qua `npx skills find`, đọc SKILL.md
trước khi cài, cập nhật bằng `npx skills update -g`.

## 3. Những gì tự động bị chặn

Xem bảng hook (guard-bash, guard-write, guard-read, stop-gate…) ở [README#guardrails](../README.md#guardrails).

## 4. Repo đã có `/commit`, `/push` của team

Dùng của team. `/sdw:commit`, `/sdw:ship`… sẽ nói "this repo has /commit, use it" và dừng,
trừ khi bạn thêm `--anyway`. Verify skill (cài bằng `--verify-skill`) vẫn chạy gate trước khi
commit qua skill của team.

## 5. Thêm skill riêng cho một dự án

- Chỉ dự án này: `<repo>/.claude/skills/<tên>/SKILL.md`, rồi tự thêm một dòng
  `.claude/skills/<tên>/` vào `.git/info/exclude` **bên ngoài** khối `# >>> sdw >>>` (khối đó do
  `sdw-exclude` quản lý). Ở layout thư mục cha không phải git thì đặt ở `<cha>/.claude/skills/`,
  không cần exclude.
- Mọi dự án: `~/.claude/skills/<tên>/SKILL.md`.

```markdown
---
name: deploy-staging
description: Deploy the current branch to staging after the smoke test.
disable-model-invocation: true
---
Các bước cụ thể...
```

Skill có side effect thì luôn để `disable-model-invocation: true`. Mỗi skill model gọi được
tốn context mọi lượt — xem [memory-and-context.md](memory-and-context.md).

## 6. Nhiều agent cùng lúc

Mỗi agent một worktree (`/sdw:plan` hỏi; hoặc `sdw-wt add <slug>`); luật đầy đủ ở [cmux.md](cmux.md).

## 7. Dùng qua AionUi

Project/Conversation, quyền, Team, điều khiển từ điện thoại: [aionui.vi.md](aionui.vi.md).

## 8. Ngày cuối — `/sdw:offboard`

1. Liệt kê việc dở: branch chưa merge/chưa push, PR đang mở, ticket, worktree → ghi handoff.
2. Danh sách credential (chỉ tên) → **bạn tự revoke** trên GitHub/Jira/Figma/cloud.
3. Một lần xác nhận, rồi xoá dữ liệu trong dự án: `.sdw/`, khối exclude, `e2e/.auth`, mọi
   worktree, Keychain `sdw:*` của dự án, cache. Memory, transcript (`~/.claude/projects/<slug>`),
   file-history và các dòng history.jsonl nằm ngoài dự án nên guard chặn xoá: offboard **in lệnh**
   để bạn tự chạy sau khi thoát session.
4. Dữ liệu test QA đã tạo: liệt kê theo môi trường, xoá chỉ khi bạn đồng ý từng môi trường.
5. Docker volume DB (nhất là bản copy production), backup, thư mục Drive đồng bộ → xoá theo
   hợp đồng. Bài học chung viết lại **không có chi tiết khách hàng** rồi mới đưa vào global memory.

Plugin vẫn giữ nguyên cho dự án sau.
