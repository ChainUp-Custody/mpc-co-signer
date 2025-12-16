# MPC Co-Signer

[English](README_EN.md) | 中文

MPC Co-Signer 是 ChainUp Custody 提供的协同签名服务程序，用于保障资产安全。它部署在客户的私有环境中，与 ChainUp Custody 系统配合完成交易的协同签名。

## 功能特性

- **私钥分片管理**: 客户私钥分片本地加密存储，确保资产控制权。
- **协同签名**: 参与 MPC 签名计算，无需完整私钥即可完成交易签名。
- **SGX 安全防护**: 支持 Intel SGX (Software Guard Extensions) 部署，提供硬件级密钥保护。
- **自动化部署**: 提供一键安装脚本，支持标准模式和 SGX 模式，简化部署流程。
- **安全验证**: 支持回调验证与 RSA 签名验证，确保交易请求的合法性。

## 快速开始

### 1. 下载与安装

```bash
# 赋予脚本执行权限
chmod +x install.sh

# 运行安装脚本
./install.sh
```

安装脚本启动后，您可以选择安装模式：
1. **Standard (标准模式)**: 适用于普通 Linux 服务器。
2. **SGX (安全模式)**: 适用于支持 Intel SGX 的服务器，提供更高的安全性。

脚本会自动：
- 下载适合您系统的 `co-signer` 程序（SGX 模式下会自动进行签名和打包）。
- 引导您完成密钥生成和配置。
- 生成启动和停止脚本。

### 2. 启动服务

```bash
./startup.sh
```

### 3. 停止服务

```bash
./stop.sh
```

## 文档索引

- [部署文档 (Deployment Guide)](docs/DEPLOY.md): 详细的安装、配置和环境要求说明。
- [使用文档 (Usage Guide)](docs/USAGE.md): 命令行工具使用说明及日常运维指南。

## 目录结构

```
co-signer/
├── co-signer           # 主程序二进制文件
├── install.sh          # 安装脚本
├── startup.sh          # 启动脚本 (安装后生成)
├── stop.sh             # 停止脚本 (安装后生成)
├── conf/               # 配置文件目录
│   ├── config.yaml     # 主配置文件
│   └── keystore.json   # 加密密钥存储
├── docs/               # 文档目录
└── README.md           # 项目说明
```

## 客服支持

如遇到问题，请联系 ChainUp Custody 技术支持或查阅 [官方文档](https://custodydocs-zh.chainup.com/)。
