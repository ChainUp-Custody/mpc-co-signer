# Custody Co-Signer 一键部署 Skill（用户说明）

本文档重点说明：

- 部署过程中，用户需要提供或亲自操作的事项
- 部署完成后，用户必须执行的事项

## 用户需要提供什么

必填：

- `SSH_CMD`：目标服务器的完整 SSH 命令（例如：`ssh -l root -p 22 <SERVER_IP>`）

可选（仅在你需要覆盖默认值时提供）：

- `WITHDRAW_CALLBACK_URL`
- `WEB3_CALLBACK_URL`
- `REMOTE_WORKDIR`（默认：`/data/co-signer`）

无需提前提供：

- Cookie（`COINXMAN-SSO`）
- Workstation ID
- Google 验证码

## 部署过程中用户需要操作什么

Agent 会自动执行绝大多数步骤，但以下节点需要用户参与：

1. 选择语言

- 部署开始第一步，由用户选择中文或英文。

2. 扫码登录获取 Console Cookie（Phase 2）

- Agent 执行 `scripts/get_custody_cookie.py` 并在聊天中展示二维码。
- 用户使用 Custody App 扫码并完成登录。
- 仅在脚本失败时，才回退为用户手动粘贴 `COINXMAN-SSO`。

3. 选择工作站

- Agent 从 Console API 拉取工作站列表。
- 用户选择本次部署目标工作站。

4. 在保存 API 前一刻输入 Google 验证码

- 仅在即将调用 `POST /api/mpc/api/save` 时输入Custody App `google_code`。
- 不要提前提供（有效期很短）。

5. 在 Custody App 中审批

- API 创建/更新请求提交后，用户必须在 Custody App 完成审批。
- Agent 会等待用户确认审批完成后再继续。

## 部署完成后用户必须执行（强制）

部署完成后，用户必须尽快完成以下动作：

1. 立即修改 co-signer 初始密码

- 服务器执行：`cd <安装目录> && ./co-signer -reset-password`

2. 修改真实回调地址

- 编辑 `<安装目录>/conf/config.yaml`
- 将 `custom_service.withdraw_callback_url` 设置为生产真实回调 URL。

3. 使用新密码重启服务

- 执行：`./stop.sh` 然后 `./startup.sh`
- 按提示交互输入新密码。

4. 删除 AI Agent 的 SSH 权限

- 从 `~/.ssh/authorized_keys` 中移除部署时使用的临时公钥。

5. 核对防火墙/网络放行

- 入站：允许 Custody 源 `54.254.7.206` 访问 co-signer 端口（默认 `28888`）。
- 出站：允许 co-signer 服务器访问 `54.251.87.91:443`。

6. 在 Custody App 完成签名私钥分享/刷新

- 在 Co-Signer 管理流程中完成私钥分享或刷新相关步骤。

## 用户侧安全建议

- 初始密码属于高敏感信息，必须立即轮换并安全保管。
- 部署身份不要保留长期自动化 SSH 访问。
- 自定义验签私钥与解密后的敏感信息请放入受控密钥管理系统。

## 主要脚本入口

- `scripts/deploy_remote_install.sh`（Phase 1）
- `scripts/get_custody_cookie.py`（Phase 2 Cookie）
- `scripts/console_api_ops.py`（Phase 2 Console API）
- `scripts/cosigner_remote_ops.py`（Phase 3 远程操作）
- `scripts/generate_secret_bundle.sh`（Phase 4 密钥包）

## 触发部署的指令

使用以下指令在聊天中触发一键部署：

```
@copilot /skill custody-co-signer-one-click 部署 co-signer
```

或直接描述：

```
我要部署 ChainUp Custody Co-Signer，服务器是 ssh -l root -p 22 <YOUR_SERVER_IP>
```

Agent 会自动引导你完成全部部署步骤。
