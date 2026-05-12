# 🔒 Security Notice - 敏感信息保护

## Important ⚠️

所有示例代码和文档中使用的是**通用占位符**，而非真实的客户数据。

## 敏感数据保护规则

### 1️⃣ 服务器地址

- **占位符**: `<SERVER_IP>`
- **示例**: `ssh -l root -p 22 <SERVER_IP>`
- **实际值**: 替换为您的真实服务器 IP (例如：`<SERVER_IP>`)
- **重要**: 每个客户的服务器地址都不同，**永远不要在代码库或文档中暴露真实地址**

### 2️⃣ 工作站 ID

- **占位符**: `<WORKSTATION_ID>`
- **示例**: `--workstation-id <WORKSTATION_ID>`
- **实际值**: 替换为您在 Custody Console 中的工作站 ID (例如：`12598`)
- **重要**: 这是客户特定的标识符，**永远不要在共享文档中硬编码**

### 3️⃣ 认证信息

- **Cookie**: 自动生成，不在代码中存储
- **Password**: 加密存储在 bundle 中，不在服务器持久化
- **RSA Keys**: 不在代码或日志中暴露

## 使用指南

### ✅ 正确方式

```bash
# 使用占位符
./orchestrate_deployment.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
  --workstation-id <WORKSTATION_ID>

# 或通过环境变量
export SERVER_IP="your.server.ip"
export WORKSTATION_ID="your_ws_id"

./orchestrate_deployment.sh \
  --ssh-cmd "ssh -l root -p 22 ${SERVER_IP}" \
  --workstation-id ${WORKSTATION_ID}
```

### ❌ 错误方式（请勿使用）

```bash
# ❌ 硬编码真实 IP 地址
./orchestrate_deployment.sh \
  --ssh-cmd "ssh -l root -p 22 <SERVER_IP>" \
  --workstation-id 12598

# ❌ 在代码中存储敏感信息
SSH_CMD="ssh -l root -p 22 <SERVER_IP>"
WS_ID="12598"
```

## 文档中的占位符说明

所有本项目中的文档使用以下标准占位符：

| 占位符             | 含义                         | 替换为             |
| ------------------ | ---------------------------- | ------------------ |
| `<SERVER_IP>`      | 目标服务器 IP 地址           | 您的服务器 IP      |
| `<WORKSTATION_ID>` | Custody Console 工作站 ID    | 您的工作站 ID      |
| `<COOKIE>`         | 认证 Cookie (auto-generated) | COINXMAN-SSO 值    |
| `<PASSWORD>`       | 生成的 24 字符密码           | 从加密 bundle 解密 |
| `<APP_ID>`         | 从 Console API 获取          | 生成的应用 ID      |

## Git 提交安全建议

✅ **安全的提交**:

```bash
# 在提交前检查是否有真实敏感信息
git diff HEAD~ | grep -E "<SERVER_IP>|<WORKSTATION_ID>|ssh root@"

# 使用占位符提交
git add .
git commit -m "Update deployment docs with safe placeholders"
```

❌ **危险操作**:

```bash
# 不要提交包含真实 IP 或工作站 ID 的文件
git add orchestrate_deployment.sh  # (如果有硬编码值)
git commit -m "..."

# 不要提交日志或配置文件
git add nohup.out config.yaml
```

## 如果不小心暴露了敏感信息

如果您意外地在提交中暴露了敏感信息，请立即：

1. **撤销提交** (如果还未 push):

```bash
git reset --soft HEAD~1
```

2. **清理敏感信息** (如果已 push):

```bash
# 从 git 历史中删除
git filter-branch --tree-filter 'sed -i "s/<REAL_SERVER_IP>/<SERVER_IP>/g" *.sh'
git push --force-with-lease
```

3. **轮换凭据**:
   - 更改服务器密码
   - 重新生成 SSH 密钥
   - 通知 ChainUp Custody 团队

## 环境变量方法 (推荐)

使用环境变量而不是硬编码：

```bash
#!/bin/bash

# ~/.co-signer-env (不提交到 git)
export SERVER_IP="your.server.ip"
export WORKSTATION_ID="your_workspace_id"
export CUSTODY_COOKIE="your_cookie"

# 在脚本中使用
source ~/.co-signer-env

./orchestrate_deployment.sh \
  --ssh-cmd "ssh -l root -p 22 ${SERVER_IP}" \
  --workstation-id ${WORKSTATION_ID}
```

**不要提交** `~/.co-signer-env`，添加到 `.gitignore`:

```bash
echo "~/.co-signer-env" >> ~/.gitignore
```

## .gitignore 建议

```bash
# 敏感配置文件
.env
.env.local
*.conf
*.config
.co-signer-env

# 日志和临时文件
*.log
nohup.out
/tmp/
/artifacts/

# SSH 密钥
*.pem
*.key
*.pub
id_rsa*

# 密码和令牌
.password
.token
.secret
```

## 文档审查清单

在提交或分享任何文档前，检查以下项目：

- [ ] 没有真实的 IP 地址 (使用 `<SERVER_IP>`)
- [ ] 没有真实的工作站 ID (使用 `<WORKSTATION_ID>`)
- [ ] 没有真实的密码或 Cookie
- [ ] 没有真实的 SSH 连接字符串
- [ ] 所有示例都使用占位符或通用值
- [ ] 未来的读者可以安全地复制粘贴示例

## 部署后额外安全动作（与技能清单保持一致）

在完成初始密码修改后，必须立即执行：

1. 编辑 `conf/config.yaml`
2. 将 `custom_service.withdraw_callback_url` 修改为真实生产回调地址
3. 保存后按流程重启服务使配置生效

## 相关文档

- [SKILL.md](./SKILL.md) - 使用安全的占位符
- [MODULAR_ARCHITECTURE.md](./MODULAR_ARCHITECTURE.md) - 所有示例都使用占位符

## 支持

如有安全顾虑，请：

1. 检查本文档
2. 查看示例中使用的占位符
3. 使用环境变量而不是硬编码值

---

**Last Updated**: 2024  
**Status**: ✅ All sensitive data replaced with safe placeholders

此公告确保所有文档和示例都遵循安全最佳实践，保护客户数据隐私。
