# RobustMQ Nix Flake

这个 Nix flake 为 RobustMQ 项目提供了完整的构建和开发环境支持。

## 功能特性

- 🚀 **完整构建支持**: 支持构建服务器组件和 Kubernetes 操作符
- 🔧 **开发环境**: 提供包含所有必需工具的开发 shell
- 📚 **文档构建**: 支持构建项目文档
- 🎯 **交叉编译**: 支持多平台交叉编译
- 🧪 **测试支持**: 集成测试环境

## 快速开始

### 先决条件

- 安装 [Nix](https://nixos.org/download.html) 包管理器（推荐使用 flakes）
- 启用 flakes 功能：

  ```bash
  echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
  ```

### 构建项目

```bash
# 构建服务器组件（默认）
nix build

# 构建服务器组件
nix build .#server

# 构建 Kubernetes 操作符
nix build .#operator

# 构建所有组件
nix build .#all

# 构建文档
nix build .#docs
```

### 交叉编译

```bash
# 构建 Linux x86_64 版本
nix build .#server-x86_64-linux

# 构建 Linux ARM64 版本
nix build .#server-aarch64-linux

# 构建 Windows x86_64 版本（仅在 Linux 上）
nix build .#server-x86_64-windows
```

### 开发环境

```bash
# 进入开发 shell
nix develop

# 或使用 direnv（推荐）
echo "use flake" > .envrc
direnv allow
```

开发 shell 包含以下工具：

- Rust 工具链（rustc, cargo, rustfmt, clippy）
- Go 工具链（用于操作符开发）
- Node.js 和 npm（用于文档）
- 各种开发工具（git, curl, jq, kubectl 等）

### 运行应用程序

```bash
# 运行服务器
nix run .#server

# 运行操作符
nix run .#operator

# 或者直接使用构建结果
./result/libs/broker-server
```

### 开发工作流

在开发 shell 中，您可以使用熟悉的命令：

```bash
# Rust 开发
cargo build              # 构建项目
cargo test               # 运行测试
cargo clippy             # 代码检查
cargo fmt                # 格式化代码
cargo watch -x build     # 监视文件变化并构建

# Go 开发（操作符）
cd operator
go build                 # 构建操作符
go test                  # 运行测试

# 文档开发
npm run docs:dev         # 启动文档开发服务器
npm run docs:build       # 构建文档
```

## 构建输出

构建完成后，您会在 `result` 目录中找到以下结构：

```text
result/
├── bin/           # Shell 脚本
├── libs/          # 编译的二进制文件
│   ├── broker-server
│   ├── cli-command
│   └── cli-bench
├── config/        # 配置文件
└── docs/          # 文档文件
```

## 环境变量

flake 会自动设置以下环境变量：

- `LIBCLANG_PATH`: clang 库路径
- `PKG_CONFIG_PATH`: pkg-config 路径
- `OPENSSL_DIR`: OpenSSL 安装路径
- `PROTOC`: Protocol Buffers 编译器路径

## CI/CD 集成

您可以在 CI/CD 管道中使用此 flake：

```yaml
# GitHub Actions 示例
- name: Build with Nix
  uses: cachix/install-nix-action@v18
  with:
    extra_nix_config: experimental-features = nix-command flakes

- name: Build server
  run: nix build .#server

- name: Run tests
  run: nix develop --command cargo test
```

## 自定义构建

如果需要自定义构建过程，您可以：

1. Fork 此项目
2. 修改 `flake.nix` 中的构建逻辑
3. 提交您的更改

## 故障排除

### 常见问题

1. **构建失败**: 确保您的 Nix 版本支持 flakes
2. **权限问题**: 检查文件权限和 Nix 守护进程状态
3. **网络问题**: 某些依赖可能需要从网络下载

### 清理缓存

```bash
# 清理构建缓存
nix-collect-garbage -d

# 清理特定构建
nix store delete ./result
```

## 贡献

欢迎对此 flake 进行改进！请遵循以下步骤：

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 创建 Pull Request

## 许可证

此 flake 遵循与 RobustMQ 项目相同的 Apache 2.0 许可证。
