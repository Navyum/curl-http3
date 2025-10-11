# curl-http3-dockerfile

一个支持HTTP/3的curl Docker镜像，基于Debian构建，集成了Cloudflare的quiche库。

## 功能特性

- ✅ 支持HTTP/3协议
- ✅ 基于Debian 12-slim，体积优化
- ✅ 集成httpstat工具
- ✅ 多平台支持（amd64, arm64）
- ✅ 自动CI/CD构建

## 使用方法

### 直接使用

```bash
# 拉取最新镜像
docker pull ghcr.io/your-username/curl-http3:latest

# 运行curl命令
docker run --rm ghcr.io/your-username/curl-http3-dockerfile:latest curl --version

# 测试HTTP/3
docker run --rm ghcr.io/your-username/curl-http3-dockerfile:latest curl --http3 https://cloudflare-quic.com/
```

### 使用httpstat

```bash
# 使用httpstat分析HTTP请求
docker run --rm -v $(pwd):/opt ghcr.io/your-username/curl-http3-dockerfile:latest /opt/httpstat.sh https://example.com
```

## 本地构建

```bash
# 构建镜像
docker build -t curl-http3 .

# 运行测试
docker run --rm curl-http3 curl --version
```

## CI/CD

本项目使用GitHub Actions进行自动化构建和发布：

- **触发条件**：
  - 推送到main/master分支
  - 创建tag（格式：v*）
  - 创建Pull Request

- **构建流程**：
  1. 代码检查（Dockerfile语法检查）
  2. 功能测试（curl版本、HTTP/3支持、httpstat脚本）
  3. 多平台构建（amd64, arm64）
  4. 推送到GitHub Container Registry
  5. 安全扫描

- **镜像标签**：
  - `latest`：最新主分支构建
  - `v1.0.0`：版本标签
  - `main`：主分支构建

## 镜像信息

- **基础镜像**：debian:12-slim
- **curl版本**：8.2.1
- **quiche版本**：0.18.0
- **支持协议**：HTTP/1.1, HTTP/2, HTTP/3

## 许可证

MIT License
