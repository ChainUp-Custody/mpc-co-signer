# MPC Co-Signer 使用文档

本文档介绍了 `co-signer` 程序的命令行工具和日常使用方法。

## 命令行工具

`co-signer` 程序内置了多种实用工具，用于密钥管理、网络诊断和配置检查。

### 基本用法
```bash
./co-signer [OPTIONS]
```

### 核心命令

| 选项 | 说明 |
|------|------|
| `-server` | 启动 Co-Signer 服务模式（通常通过 `startup.sh` 调用） |
| `-v` | 显示版本信息 |
| `-h` | 显示帮助信息 |

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
目前不支持直接修改密码。如果需要修改密码，需要重新运行 `install.sh` 或手动重新生成 `keystore.json`。

### 更新程序
1. 停止服务：`./stop.sh`
2. 替换 `co-signer` 二进制文件。
3. 启动服务：`./startup.sh`
