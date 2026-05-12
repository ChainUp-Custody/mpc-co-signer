# 快速参考卡 - Co-Signer 一键部署

## Cookie 获取（两种策略）

### 策略 1：Playwright 浏览器工具（推荐）

Agent 使用 VS Code 内置 Playwright 浏览器工具：

1. `open_browser_page` → 打开 `https://custody.chainup.com/login`
2. `screenshot_page` → 截图二维码显示在聊天窗口
3. 用户用 Custody App 扫码
4. Agent 轮询 URL 变化（离开 `/login`）
5. `run_playwright_code` → CDP `Network.getCookies` 提取 HttpOnly cookie

### 策略 2：用户手动输入（兜底）

1. 用户自己打开浏览器登录 custody.chainup.com
2. DevTools → Application → Cookies → 复制 `COINXMAN-SSO`
3. 粘贴到聊天窗口

---

## 部署命令

```bash
./scripts/deploy_custody_cosigner.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
  --cookie "<COINXMAN_SSO_VALUE>" \
  --workstation-id <WORKSTATION_ID>
```

## Phase 1 版本校验规则

- 目标版本默认使用 GitHub releases 最新 tag（或显式 `COSIGNER_VERSION`）
- 即使远端已存在 `./co-signer`，也必须执行 `./co-signer -v` 解析版本并与目标 tag 比对
- 仅在版本完全一致时复用；否则必须重新下载对应版本

---

## 文件清单

| 文件                         | 说明             |
| ---------------------------- | ---------------- |
| `deploy_custody_cosigner.sh` | 一键部署编排脚本 |
| `deploy_remote_install.sh`   | 远程部署执行脚本 |
| `generate_secret_bundle.sh`  | 加密密钥包生成   |
| `SKILL.md`                   | 完整技能文档     |

---

## 安全模型

| 项目     | 说明                               |
| -------- | ---------------------------------- |
| 密码长度 | 24 字符强随机                      |
| 密码存储 | **不落盘**，仅内存中处理           |
| 密码传输 | 进程替换 `<(printf ...)` 不经磁盘  |
| 密码展示 | 部署末尾明文展示 + 安全横幅        |
| 启动方式 | TTY 交互输入，不在 argv/env 中暴露 |
| Cookie   | Playwright CDP 提取 / 用户手动输入 |

---

## 后续操作（客户必做）

1. 登录服务器修改密码：`./co-signer -reset-password`
2. 修改 `withdraw_callback_url` 为真实回调地址：编辑 `conf/config.yaml` 中 `custom_service.withdraw_callback_url`
3. 删除 agent SSH 公钥：`vi ~/.ssh/authorized_keys`
4. Custody App → MPC 工作站 → 刷新私钥到 co-signer

---

## 成功判定门禁（防误报）

出现以下任一情况，**不得提示“部署成功”**：

1. `POST /api/mpc/api/save` 返回码不是 `0` / `110188` 已审批可验证状态。
2. `GET /api/mpc/api/detail` 不是 `code=0`。
3. API `co_signer_rsa` 与服务器 `./co-signer -show-rsa` 的 Co-Signer RSA 不一致（标准化后精确匹配）。
4. API `co_signer_url` 不等于 `http://<SERVER_IP>:<PORT>`。
5. API `believe_ips` 未包含服务器 IP。

审批规则：

- `code=0` 且有 `trade_no`：提示用户在 App 审批，审批后再 detail 校验。
- `code=110188`：表示已有待审批单，禁止重提，等待审批后再 detail 校验。
- `code=110007`：Google code 过期，获取新验证码后重提。
- `code=110909`：Cookie 失效，重新获取 cookie。
