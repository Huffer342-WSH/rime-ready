# rime-ready

`rime-ready` 为 Ubuntu 22.04 提供与新版雾凇拼音匹配的 Rime 运行环境。目前支持 Ubuntu 22.04 amd64，包含：

- librime 1.17.0；
- 与 librime 匹配的 librime-lua；
- 与 librime 匹配的 librime-octagram；
- `rime_deployer` 等命令行工具；
- 签名 APT 软件源；
- 雾凇拼音和可选万象 Gram 的一键安装脚本。

上游版本固定在 [`versions.env`](versions.env)，本地构建、GitHub Actions 和发布软件包使用相同版本。

相关上游项目：

- [雾凇拼音（rime-ice）](https://github.com/iDvel/rime-ice)
- [万象语法模型（RIME-LMDG）](https://github.com/amzxyz/RIME-LMDG)

rime-ready 的 deb 不包含这两个项目的用户配置或模型文件；一键脚本会按所选预设从上游 Release 下载。

## Ubuntu 22.04 安装新版雾凇的问题

Ubuntu 22.04 官方仓库提供的是 librime 1.7.3。新版雾凇使用了较新的 Lua 模块加载方式，只安装 Ubuntu 自带的 `fcitx5-rime` 或 `ibus-rime` 时，可能无法正确加载和部署完整方案。

问题不在 Fcitx5 或 IBus 本身，而在它们最终加载的 Rime 运行库及插件版本较旧。只单独替换 `librime.so` 也不安全，因为 librime、Lua 插件、Octagram 插件和命令行工具需要使用彼此匹配的版本。

`rime-ready` 将以下四个组件构建为 Ubuntu 同名软件包，通过 APT 一起升级：

```text
librime1
librime-bin
librime-plugin-lua
librime-plugin-octagram
```

完整的雾凇输入法由三部分组成：

1. **输入法前端**：Ubuntu 提供的 `fcitx5-rime` 或 `ibus-rime`。
2. **Rime 运行环境**：rime-ready APT 软件源提供的四个新版软件包。
3. **用户输入方案**：雾凇配置、可选的万象 Gram，以及部署生成的用户目录文件。

需要完整安装输入法，可以使用后文的一键安装脚本。

## 通过 APT 软件源安装运行环境

rime-ready 使用 GitHub Pages 发布签名 APT 仓库：

```text
deb [arch=amd64 signed-by=/usr/share/keyrings/rime-ready-archive-keyring.gpg] https://huffer342-wsh.github.io/rime-ready/apt/ubuntu jammy main
```

以下命令适用于 Ubuntu 22.04 amd64。

### 1. 安装下载工具

```bash
sudo apt update
sudo apt install -y ca-certificates curl
```

### 2. 安装仓库公钥

```bash
curl -fsSL \
  https://huffer342-wsh.github.io/rime-ready/keys/rime-ready-archive-keyring.gpg |
  sudo tee /usr/share/keyrings/rime-ready-archive-keyring.gpg >/dev/null
sudo chmod 0644 /usr/share/keyrings/rime-ready-archive-keyring.gpg
```

如果此前添加过旧公钥并遇到 `NO_PUBKEY E7E0727BD4AEE87A`，删除旧文件后重新执行上面的公钥安装命令：

```bash
sudo rm -f /usr/share/keyrings/rime-ready-archive-keyring.gpg
```

### 3. 添加软件源

```bash
echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/rime-ready-archive-keyring.gpg] https://huffer342-wsh.github.io/rime-ready/apt/ubuntu jammy main' |
  sudo tee /etc/apt/sources.list.d/rime-ready.list >/dev/null
sudo apt update
```

### 4. 安装 Rime 运行环境

```bash
sudo apt install -y librime1 librime-bin librime-plugin-lua librime-plugin-octagram
```

按桌面环境选择输入法前端：

```bash
sudo apt install -y fcitx5-rime
# 或
sudo apt install -y ibus-rime
```

## 一键安装雾凇

脚本目前只支持 Ubuntu 22.04 amd64。请以普通桌面用户运行，不要在命令前添加 `sudo`；脚本只在安装系统软件包时自行调用 `sudo`。

### 最常用：Fcitx5 + 雾凇

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | bash
```

默认执行以下操作：

1. 验证并添加 rime-ready APT 软件源；
2. 安装四个新版 Rime 软件包；
3. 安装 Ubuntu 的 `fcitx5-rime`；
4. 下载稳定版雾凇；
5. 备份原 Rime 用户目录；
6. 保留已有的 `rime_ice.userdb` 用户词库；
7. 部署方案，设置并启动 Fcitx5 Rime。

### 参数列表

给在线脚本传参时，参数必须写在 `bash -s --` 后面：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- <参数>
```

| 参数                    | 说明                                                         |
| ----------------------- | ------------------------------------------------------------ |
| `--apt`                 | 从 rime-ready APT 软件源安装四个运行库软件包，默认方式。     |
| `--download`            | 绕过 APT 软件源，从最新 GitHub Release 下载并校验四个 deb。  |
| `--build`               | 下载固定版本的上游源码，在本机编译并安装四个 deb。           |
| `--deb <目录/文件/URL>` | 安装指定的 deb 集合；可重复使用。                            |
| `--preset runtime-only` | 只安装 Rime 运行库和命令行工具，不安装输入法前端和用户方案。 |
| `--preset ice`          | 安装运行库、输入法前端和稳定版雾凇，默认预设。               |
| `--preset ice-gram`     | 在 `ice` 基础上安装万象 Gram。                               |
| `--with-gram`           | `--preset ice-gram` 的简写。                                 |
| `--frontend fcitx5`     | 使用 Fcitx5 前端，默认值。                                   |
| `--frontend ibus`       | 使用 IBus 前端。                                             |
| `--no-activate`         | 安装并部署方案，但不修改或启动当前用户的输入法前端。         |
| `--no-start`            | 修改输入法设置，但不立即启动前端。                           |
| `-h`、`--help`          | 显示帮助。                                                   |

### 常用组合

安装雾凇和万象 Gram，但不修改当前输入法配置：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset ice-gram --no-activate
```

使用 IBus 安装雾凇：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset ice --frontend ibus
```

只安装 Rime 运行环境：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset runtime-only
```

只设置输入法，不立即启动前端：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset ice --no-start
```

### 其他安装来源

从最新 GitHub Release 直接下载 deb：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --download --preset ice
```

在本机从固定源码编译；该过程会下载上游源码并安装编译依赖：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --build --preset ice
```

克隆仓库后安装本地 deb：

```bash
./install.sh --deb ./dist --preset runtime-only
```

也可以重复传入四个本地文件或 URL：

```bash
./install.sh \
  --deb https://example.com/librime1.deb \
  --deb https://example.com/librime-bin.deb \
  --deb https://example.com/librime-plugin-lua.deb \
  --deb https://example.com/librime-plugin-octagram.deb \
  --preset ice
```

`install.sh` 是可独立在线运行的脚本，不依赖仓库中的 `scripts/` 目录。它只通过 `sudo` 修改系统软件包；用户目录中的 Rime 配置始终以当前桌面用户身份修改。

## 软件包说明

APT 仓库和 GitHub Release 都提供以下四个 Ubuntu 同名软件包：

```text
librime1
librime-bin
librime-plugin-lua
librime-plugin-octagram
```

这些软件包使用比 Ubuntu 22.04 官方版本更高的 Debian 版本号。APT 会将它们识别为正常升级，不会在后续 `apt upgrade` 时自动降级到 Jammy 的 librime 1.7.3。

软件包使用 Ubuntu 标准路径：

```text
/usr/lib/x86_64-linux-gnu/librime.so.1
/usr/lib/x86_64-linux-gnu/rime-plugins/librime-lua.so
/usr/lib/x86_64-linux-gnu/rime-plugins/librime-octagram.so
/usr/bin/rime_deployer
```

所有文件都由 `dpkg` 记录所有权。软件包不包含用户输入方案，不修改 Fcitx5/IBus 配置，也不会自动激活输入法。

## 只安装或更新雾凇

已经安装新版 Rime 运行环境后，可以克隆仓库并单独更新雾凇。

Fcitx5：

```bash
scripts/install-rime-ice.sh
```

IBus：

```bash
scripts/install-rime-ice.sh --frontend ibus
```

只部署方案，不修改当前输入法：

```bash
scripts/install-rime-ice.sh --no-activate
```

安装前，脚本会把原配置目录重命名为带时间戳的备份目录，并保留已有的 `rime_ice.userdb`。

只设置输入法前端、不重新安装方案：

```bash
scripts/configure-input-method.sh --frontend fcitx5
# 或
scripts/configure-input-method.sh --frontend ibus
```

## APT 仓库结构

APT 仓库通过 GitHub Pages 发布，目录按发行版家族、版本代号、组件和架构组织：

```text
apt/
├── ubuntu/
│   ├── dists/
│   │   └── jammy/
│   │       └── main/binary-amd64/
│   └── pool/
│       └── jammy/main/
└── debian/                  # 后续支持 Debian 时添加
    ├── dists/<codename>/
    └── pool/<codename>/
```

每个平台在 `platforms/<target>/platform.env` 中声明仓库家族、suite、component、architecture 和 Release 文件匹配模式。发布流程使用独立 APT 密钥生成 `InRelease` 和 `Release.gpg`，并保留 By-Hash 索引，避免 GitHub Pages CDN 缓存不同步。

APT 私钥由仓库 Secret `APT_GPG_PRIVATE_KEY` 提供，离线备份不能提交到 Git。需要从已有 GitHub Release 重建 APT 仓库时，可以手动运行 `Publish APT repository` Workflow。

移除软件源但保留当前已安装软件：

```bash
sudo rm -f /etc/apt/sources.list.d/rime-ready.list
sudo rm -f /usr/share/keyrings/rime-ready-archive-keyring.gpg
sudo apt update
```

## 开发文档

- [手动编译教程](docs/MANUAL_BUILD.md)：准备 Ubuntu 22.04 环境，分步编译、测试、打包和安装 deb。
- [设计说明](docs/DESIGN.md)：构建数据流、软件包拆分、安装流程、APT 仓库和发布设计。

## 本地构建与测试

下面只列出常用命令，完整步骤和注意事项见[手动编译教程](docs/MANUAL_BUILD.md)。

分步构建：

```bash
scripts/build.sh --target ubuntu-22.04
scripts/test-build.sh ubuntu-22.04
scripts/package-deb.sh --target ubuntu-22.04 --reuse-build
```

输出目录：

```text
dist/*.deb
dist/SHA256SUMS-*
```

强制清理后重新构建：

```bash
scripts/build.sh --target ubuntu-22.04 --clean
```

运行发布前完整检查：

```bash
scripts/ct.sh --target ubuntu-22.04
```

使用复用容器执行 CT：

```bash
scripts/docker-ct.sh --target ubuntu-22.04
scripts/docker-ct.sh --reuse-build
scripts/docker-ct.sh --rebuild-image
```

默认容器镜像名为 `rime-ready-ubuntu22-ct:local`，可通过 `RIME_READY_CT_IMAGE` 覆盖。

CT 会执行以下检查：

1. 编译固定版本的 librime、Lua 和 Octagram；
2. 运行 librime 单元测试；
3. 检查动态库依赖；
4. 生成四个标准 deb，并以 Lintian error 作为失败条件；
5. 检查 APT 仓库目录、索引、By-Hash 和公钥；
6. 安装 Fcitx5/IBus 前端并检查 ABI；
7. 部署稳定版雾凇；
8. 模拟输入 `nihao`，确认候选和提交文本包含“你好”。

## GitHub Actions

- `build.yml`：`main` Push 后运行完整 CT，只上传 CI 产物，不发布版本。
- `release.yml`：推送 `v*` Tag 或手动触发后运行完整 CT；成功后发布 GitHub Release，并更新签名 APT 仓库。
- `apt-repository.yml`：从已有 GitHub Release 手动重建某个平台的 APT 仓库。
- `upstream-watch.yml`：每周检查稳定上游版本；发现新版后更新固定版本并调度 Release Workflow。

Release Tag 默认格式：

```text
v<RIME_VERSION>-r<PACKAGE_REVISION>
```

例如：

```text
v1.17.0-r1
```

增加平台时，需要：

1. 新增 `platforms/<target>/platform.env` 和构建依赖；
2. 声明目标发行版、APT suite、component、architecture 和 Release 文件模式；
3. 将目标加入 GitHub Actions Matrix。

### 上游版本记录

仓库使用两个文件记录上游状态：

- `versions.env`：下一次构建使用的 librime、插件和雾凇版本。
- `upstream-state.json`：最近一次成功发布实际包含的上游版本。

自动轮询只跟踪 librime 正式 Release，以及形如 `YYYY.MM.DD` 的稳定版雾凇。librime-lua 和 librime-octagram 没有稳定 Release，因此只固定已经验证的提交。

只有完整 CT 和发布全部成功后，Release Workflow 才更新 `upstream-state.json`。构建或测试失败不会提前记录为成功状态。

## 卸载和恢复官方版本

移除 rime-ready 软件源，并恢复 Ubuntu 22.04 官方 Rime 软件包：

```bash
scripts/uninstall.sh
```

该脚本使用 `apt --allow-downgrades` 恢复官方版本，不会手工删除 `/usr/lib` 下的文件，也不会删除 `~/.local/share/fcitx5/rime` 中的输入方案和用户词库。

## 许可证

见 [`LICENSE`](LICENSE)。
