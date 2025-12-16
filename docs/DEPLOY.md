# MPC Co-Signer 部署文档

本文档详细说明如何在 Linux 环境下部署 MPC Co-Signer 服务。

## 1. 环境要求

- **操作系统**: Linux (推荐 Ubuntu 20.04+，SGX 模式推荐 Ubuntu 22.04)
- **硬件配置**:
  - **开发/测试环境**:
    - CPU: 2 Core+
    - RAM: 4GB+
    - Disk: 20GB+
  - **生产环境 (建议 SGX 环境部署)**:
    - CPU: 8 Core+ (支持 Intel SGX)
    - RAM: 64GB+
    - Disk: 40GB+
    - **SGX 支持**: BIOS 中需开启 SGX 支持，并安装相应驱动。
- **网络要求**:
  - 需能够访问 ChainUp Custody API (`https://openapi.chainup.com`)
  - 需开放内部端口供业务系统调用 (默认 28888)

## 2. 准备工作

在开始部署前，请确保您已经：

1. 在 ChainUp Custody 平台注册并获取了 `App ID`。
2. 准备好用于接收提现回调和 Web3 交易回调的接口 URL（可选）。
3. 获取了 ChainUp 的 RSA 公钥（可在 Custody 管理平台获取）。

## 3. 自动化部署 (推荐)

项目提供了 `install.sh` 脚本，可自动完成程序下载、密钥生成和配置初始化。

### 步骤 3.1: 获取安装包

如果您已有安装包，进入目录。如果只有脚本，请确保 `install.sh` 在工作目录中。

### 步骤 3.2: 运行安装脚本

```bash
chmod +x install.sh
./install.sh
```

### 步骤 3.3: 按照提示操作

脚本运行过程中会交互式地询问以下信息：

1. **安装类型**: 选择 `1) Standard` (标准模式) 或 `2) SGX` (安全模式)。
2. **清理确认**: 确认是否清理旧的配置文件（首次安装选 Y）。
3. **SGX 环境配置 (仅 SGX 模式)**: 脚本会自动检查并安装 `ego` 环境（仅限 Ubuntu 22.04），并自动下载、签名和打包 SGX 二进制文件。
4. **App ID**: 输入您的商户 App ID。
5. **回调地址**: 输入提现和 Web3 交易的回调 URL（如不需要可直接回车跳过）。
6. **密码设置**: 设置 Co-Signer 的启动密码（需 16 位字符）。**请务必牢记此密码，启动服务时需要使用。**
7. **ChainUp 公钥**: 输入从 Custody 平台获取的 ChainUp RSA 公钥。
8. **业务公钥**: 输入用于验证提现数据的 RSA 公钥（可选），对应私钥由客户生成，客户将提现推送到 Custody 平台时使用 RSA 私钥对提现数据进行签名。

### 步骤 3.4: 验证安装

脚本执行完毕后，会自动运行配置检查。

目录结构将包含：

- `co-signer`: 主程序
- `conf/config.yaml`: 配置文件
- `conf/keystore.json`: 密钥存储文件
- `startup.sh`: 启动脚本
- `stop.sh`: 停止脚本

## 4. 手动配置 (高级)

如果需要手动修改配置，请编辑 `conf/config.yaml`。

```yaml
main:
  # Co-signer 服务监听地址
  tcp: "0.0.0.0:28888"
  # 加密存储文件路径
  keystore_file: "conf/keystore.json"

custody_service:
  # 商户 App ID
  app_id: "YOUR_APP_ID"
  # API 域名
  domain: "https://openapi.chainup.com/"
  # 语言设置 (zh_CN 或 en_US)
  language: "en_US"

custom_service:
  # 提现回调地址
  # 该接口不仅用于提现二次确认，还用于 Co-Signer 启动时的配置自检（验证公钥配置是否正确）
  # 详细协议请参考下方 "回调接口说明"
  withdraw_callback_url: "http://your-service/callback/withdraw"
  # Web3 交易回调地址
  web3_callback_url: "http://your-service/callback/web3"
```

## 5. 回调接口说明

### 提现回调接口 (`withdraw_callback_url`)

该接口有两个用途：

1. **配置自检**: 当运行 `./co-signer -check-conf` 时，会调用此接口验证公钥配置。
2. **提现二次确认**: 当发起提现时，Co-Signer 会调用此接口请求确认。

#### 配置自检请求格式

当 `type` 为 `verify_public_hash` 时，表示这是一个配置自检请求。

**请求参数 (POST JSON):**

```json
{
  "app_id": "YOUR_APP_ID",
  "client_system_pubkey_hash": "SHA256_HASH_OF_CLIENT_PUBKEY",
  "verify_sign_pub_hash": "SHA256_HASH_OF_VERIFY_SIGN_PUBKEY",
  "type": "verify_public_hash"
}
```

**响应参数 (JSON):**

```json
{
  "client_system_pubkey_hash_valid": "SUCCESS",
  "verify_sign_pub_hash_valid": "SUCCESS"
}
```

#### 提现二次确认请求格式

当 `type` 为 `sign_start` 时，表示这是一个提现二次确认请求。

**请求参数 (POST JSON):**

```json
{
  "type": "sign_start",
  "withdraw_id": 12345,
  "request_id": "unique_request_id",
  "from": "address_from",
  "to": "address_to",
  "amount": "100.5",
  "symbol": "ETH",
  "memo": "optional_memo",
  "outputs": "optional_outputs"
}
```

**响应参数 (String):**

返回 `SUCCESS` 字符串表示确认通过，其他返回值表示拒绝。

## 6. 服务管理

### 启动服务

```bash
./startup.sh
```

启动时需要输入之前设置的密码。

### 停止服务

```bash
./stop.sh
```

### 查看日志

日志默认输出到 `nohup.out` 

```bash
tail -f nohup.out
```

## 7. 附录：公钥 Hash 计算示例

在配置自检接口中，`client_system_pubkey_hash` 和 `verify_sign_pub_hash` 的计算方式为：使用 `app_id` 作为密钥，对公钥字符串（去除 PEM 头尾和换行符）进行 HMAC-SHA256 计算，并输出十六进制字符串。

### Java 示例

```java
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public static String getSha256HashHex(String secret, String message) {
    try {
        // 去除 PEM 头尾和换行符
        message = message.replace("\n", "")
                         .replace("-----BEGIN PUBLIC KEY-----", "")
                         .replace("-----END PUBLIC KEY-----", "");

        Mac sha256_HMAC = Mac.getInstance("HmacSHA256");
        SecretKeySpec secret_key = new SecretKeySpec(secret.getBytes(), "HmacSHA256");
        sha256_HMAC.init(secret_key);
        byte[] bytes = sha256_HMAC.doFinal(message.getBytes("UTF-8"));
        return byteArrayToHexString(bytes);
    } catch (Exception e) {
        e.printStackTrace();
        return "";
    }
}

private static String byteArrayToHexString(byte[] b) {
    StringBuilder hs = new StringBuilder();
    String stmp;
    for (int n = 0; b != null && n < b.length; n++) {
        stmp = Integer.toHexString(b[n] & 0XFF);
        if (stmp.length() == 1)
            hs.append('0');
        hs.append(stmp);
    }
    return hs.toString().toLowerCase();
}
```

### Go 示例

```go
import (
    "crypto/hmac"
    "crypto/sha256"
    "encoding/hex"
    "strings"
)

func getSha256HashHex(secret, data string) string {
    data = strings.ReplaceAll(data, "\n", "")
    data = strings.ReplaceAll(data, "-----BEGIN PUBLIC KEY-----", "")
    data = strings.ReplaceAll(data, "-----END PUBLIC KEY-----", "")
    h := hmac.New(sha256.New, []byte(secret))
    h.Write([]byte(data))
    return hex.EncodeToString(h.Sum(nil))
}
```
