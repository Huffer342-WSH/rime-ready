# 在 Ubuntu 22.04 手动编译 rime-ready

本文说明如何从仓库固定的上游版本编译 librime、Lua 和 Octagram，并生成四个可由 APT 管理的 deb。命令默认在仓库根目录执行。

## 环境要求

当前构建目标为 Ubuntu 22.04 amd64。构建脚本会检查 `/etc/os-release`，不能在其他 Ubuntu 版本上直接构建 `ubuntu-22.04` 目标。

准备以下资源：

- 可使用 `sudo` 安装构建依赖的普通用户；
- 可访问 GitHub 的网络；
- 足够存放上游源码、中间产物和依赖构建结果的磁盘空间；
- Git 工作区中可以创建 `.build/` 和 `dist/`。

克隆仓库：

```bash
git clone https://github.com/Huffer342-WSH/rime-ready.git
cd rime-ready
```

## 版本和平台配置

[`versions.env`](../versions.env) 固定以下内容：

- librime 版本和提交；
- librime-lua 提交；
- librime-octagram 提交；
- 雾凇稳定版、Asset ID 和 SHA-256；
- deb 的发布修订号。

[`platforms/ubuntu-22.04/platform.env`](../platforms/ubuntu-22.04/platform.env) 描述 Ubuntu 22.04 的系统版本、deb 后缀和 APT 仓库位置。构建依赖记录在同目录的 `build-packages.txt`。

不要在一次构建中临时切换部分提交。librime 和两个插件需要使用经过同一轮 CT 验证的组合。

## 方法一：执行完整 CT

发布前最接近 GitHub Actions 的方式是：

```bash
scripts/ct.sh --target ubuntu-22.04
```

CT 会依次完成：

1. 安装构建依赖并编译；
2. 运行 librime 单元测试；
3. 检查动态库和插件依赖；
4. 生成四个 deb 并运行 Lintian；
5. 生成并检查 APT 仓库索引；
6. 把 deb 安装到当前系统；
7. 检查 Fcitx5 和 IBus 对新版 librime 的加载；
8. 部署雾凇并执行真实输入输出测试。

注意：CT 不只编译，它会通过 `sudo apt` 安装依赖和生成的 deb。只想生成文件时，请使用下一节的分步命令。

## 方法二：分步编译和打包

### 1. 编译

```bash
scripts/build.sh --target ubuntu-22.04
```

脚本会：

- 从 `platforms/ubuntu-22.04/build-packages.txt` 安装依赖；
- 将固定提交下载到 `.build/ubuntu-22.04/source/`；
- 构建 librime 自带的静态依赖；
- 编译 librime、Lua 和 Octagram；
- 将待打包文件安装到 `.build/ubuntu-22.04/stage/`。

重新下载源码不是每次都需要。脚本会复用已有 Git 仓库，但会强制检出 `versions.env` 指定的提交。

清理目标目录后重新编译：

```bash
scripts/build.sh --target ubuntu-22.04 --clean
```

如果已经手动准备全部依赖：

```bash
scripts/build.sh --target ubuntu-22.04 --skip-deps
```

### 2. 检查编译结果

```bash
scripts/test-build.sh ubuntu-22.04
```

该步骤运行上游测试，并检查核心库、插件和命令行程序是否存在未解析符号或错误依赖。

### 3. 生成 deb

复用上一步的 stage：

```bash
scripts/package-deb.sh --target ubuntu-22.04 --reuse-build
```

如果省略 `--reuse-build`，打包脚本会先调用构建脚本：

```bash
scripts/package-deb.sh --target ubuntu-22.04
```

输出位于：

```text
dist/librime1_<version>_amd64.deb
dist/librime-bin_<version>_amd64.deb
dist/librime-plugin-lua_<version>_amd64.deb
dist/librime-plugin-octagram_<version>_amd64.deb
dist/SHA256SUMS-ubuntu-22.04
```

### 4. 检查 APT 仓库元数据

```bash
scripts/test-apt-repository.sh ubuntu-22.04
```

该命令在临时目录生成 `Packages`、`Release` 和 By-Hash 文件，并检查软件包数量、目标架构和仓库公钥。它不会发布仓库。

### 5. 安装本地结果

```bash
sudo apt install ./dist/*.deb
```

确认版本：

```bash
dpkg-query -W -f='${Package}\t${Version}\n' \
  librime1 \
  librime-bin \
  librime-plugin-lua \
  librime-plugin-octagram
```

如果还需要输入法前端：

```bash
sudo apt install fcitx5-rime
# 或
sudo apt install ibus-rime
```

安装 deb 不会写入用户的雾凇配置。可以继续执行：

```bash
scripts/install-rime-ice.sh --no-activate
```

## 使用容器执行 CT

不希望在宿主机安装全部构建依赖时，可以使用项目提供的 Ubuntu 22.04 容器：

```bash
scripts/docker-ct.sh --target ubuntu-22.04
```

复用已有构建目录：

```bash
scripts/docker-ct.sh --reuse-build
```

构建依赖发生变化后重建基础镜像：

```bash
scripts/docker-ct.sh --rebuild-image
```

默认镜像名为 `rime-ready-ubuntu22-ct:local`，可通过 `RIME_READY_CT_IMAGE` 修改。

## 常见问题

### 当前系统不是 Ubuntu 22.04

构建脚本会拒绝继续。应使用 Ubuntu 22.04 容器或虚拟机，不要通过修改 `/etc/os-release` 绕过检查，因为生成的软件包依赖 Jammy 的 glibc、ICU 和 Boost 版本。

### 只想一条命令从源码安装

在线安装脚本提供 `--build`：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --build --preset runtime-only
```

该方式适合安装，不保留仓库中的分步测试和发布操作记录。

### 恢复 Ubuntu 官方软件包

```bash
scripts/uninstall.sh
```

该脚本会移除 rime-ready 软件源，并使用 `apt --allow-downgrades` 恢复 Ubuntu 22.04 官方版本。用户词库和输入方案不会被删除。
