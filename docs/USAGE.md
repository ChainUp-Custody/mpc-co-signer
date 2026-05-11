# MPC Co-Signer 使用文档

本文档介绍了 `co-signer` 程序的命令行工具和日常使用方法。

## 命令行工具

`co-signer` 程序内置了多种实用工具，用于密钥管理、网络诊断和配置检查。

### 基本用法

```bash
./co-signer [OPTIONS]
```

### 核心命令

| 选项      | 说明                                                  |
| --------- | ----------------------------------------------------- |
| `-server` | 启动 Co-Signer 服务模式（通常通过 `startup.sh` 调用） |
| `-v`      | 显示版本信息                                          |
| `-h`      | 显示帮助信息                                          |

### 密钥管理工具

这些工具用于生成、导入和查看 RSA 密钥及助记词。

#### 1. 生成 co-signer RSA 密钥对

生成新的 RSA 私钥。

```bash
./co-signer -rsa-gen
```

#### 2. 查看 RSA 公钥

显示当前配置的 RSA 公钥信息。

```bash
./co-signer -show-rsa
```

#### 3. 导入 co-signer RSA 私钥

如果您已有 PEM 格式的 RSA 私钥，可以使用此命令导入。

```bash
./co-signer -rsa-pri-import <key_string>
```

#### 4. 导入 ChainUp 公钥

导入 ChainUp 提供的公钥，用于验证来自 Custody 系统的消息。

```bash
./co-signer -custody-pub-import <key_string>
```

#### 5. 导入业务公钥

导入用于验证提现签名的公钥。

```bash
./co-signer -verify-sign-pub-import <key_string>
```

### 密码管理工具

#### 修改密码

修改 Co-Signer 的启动密码，将使用新密码重新加密 `keystore.json` 中的所有加密字段。

```bash
./co-signer -change-password
```

执行流程：

1. 输入当前密码（验证能否解密现有 keystore）
2. 输入新密码
3. 确认新密码
4. 自动备份旧 `keystore.json` 为 `keystore.json.bak`
5. 使用新密码重新加密所有密钥数据

> **注意**：修改密码后，`startup.sh` 启动时需要输入新密码。

### 网络与诊断工具

#### 1. 检查配置

验证 `config.yaml` 和 `keystore.json` 中的配置项是否完整且正确。

```bash
./co-signer -check-conf
```

#### 2. 网络连通性检查

检查本机 IP 是否在 Custody 白名单中，以及与 Custody 服务的连通性。

```bash
./co-signer -check-ip
```

## 常见操作流程

### 修改密码

使用内置命令行工具修改密码：

```bash
./co-signer -change-password
```

修改完成后，旧的 `keystore.json` 会自动备份为 `keystore.json.bak`。下次启动服务时请使用新密码。

### 更新程序

#### 标准模式

1. 停止服务：`./stop.sh`
2. 备份现有文件：
   ```bash
   cp co-signer co-signer.bak
   ```
3. 替换 `co-signer` 二进制文件（使用 `mpc-co-signer-static-linux` 版本）。
4. 验证配置：
   ```bash
   ./co-signer -check-conf
   ```
5. 启动服务：`./startup.sh`

#### SGX 模式

1. 停止服务：`./stop.sh`
2. 备份现有文件：
   ```bash
   cp co-signer co-signer.bak
   ```
3. 下载新版本二进制文件（使用 `mpc-co-signer-linux` 非 static 版本）。
4. 重新签名并打包 SGX Enclave：
   ```bash
   ./sgx-build.sh
   # 按提示输入二进制文件名，例如: co-signer
   # 打包完成后生成带时间戳的文件，例如: co-signer.20260508143025
   ```
5. 将生成的文件重命名为 `co-signer`：
   ```bash
   mv co-signer.20260508143025 co-signer
   ```
6. 验证配置：
   ```bash
   ./co-signer -check-conf
   ```
7. 启动服务：`./startup.sh`

> **注意**：`sgx-build.sh` 会生成带时间戳的二进制文件（如 `co-signer.20260508143025`），需通过 `mv` 命令重命名为 `co-signer` 以保持与 `startup.sh` 中的文件名一致。
