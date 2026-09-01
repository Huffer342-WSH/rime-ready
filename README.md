# rime-ready

`rime-ready` 为旧版 Linux 发行版补齐现代 Rime 运行环境，并提供独立的输入方案配置脚本。项目当前支持 Ubuntu 22.04，后续可以通过新增平台配置和 CI Matrix 支持其他 Ubuntu、Debian、Fedora 等系统。

当前构建并安装：

- librime 1.17.0
- 最新固定提交的 librime-lua
- 最新固定提交的 librime-octagram
- 与新版 librime 匹配的命令行工具

输入法前端和用户方案不包含在 deb 中。一键安装脚本可以另外安装、配置雾凇拼音和可选的万象 Gram。

上游版本固定在 [`versions.env`](versions.env)，本地构建和 GitHub Actions 使用相同源码。

## 一键安装

目前只支持 Ubuntu 22.04 amd64。以普通桌面用户运行下面的命令，不要先加 `sudo`；脚本会在安装 APT 软件包时自行调用 `sudo`：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | bash
```

`install.sh` 已包含下载 deb、源码编译、安装雾凇和设置输入法所需的全部逻辑，不依赖仓库中的 `scripts/` 目录。默认从最新 GitHub Release 下载并校验四个标准 deb，然后使用 `ice` 预设：安装 Ubuntu 的 Fcitx5 Rime 前端、安装稳定版雾凇、编译方案、设置并启动输入法。

给在线脚本传参时，把参数写在 `bash -s --` 后面：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset runtime-only
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset ice-gram
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset ice --frontend ibus
```

用户配置控制：

```bash
# 安装方案，但不修改输入法设置
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset ice --no-activate

# 设置输入法，但不立即启动前端
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --preset ice --no-start
```

需要本机编译固定版本的 Rime 时使用 `--build`。编译过程不需要先克隆本仓库，但会下载上游源码并安装编译依赖：

```bash
curl -fsSL https://raw.githubusercontent.com/Huffer342-WSH/rime-ready/main/install.sh | \
  bash -s -- --build --preset ice
```

也可以克隆仓库后执行同一个脚本：

```bash
./install.sh
./install.sh --preset ice-gram
```

安装指定的本地或远程 deb 时，使用已克隆仓库中的脚本更方便：

```bash
./install.sh --deb ./dist --preset runtime-only
./install.sh --deb https://example.com/librime1.deb \
  --deb https://example.com/librime-bin.deb \
  --deb https://example.com/librime-plugin-lua.deb \
  --deb https://example.com/librime-plugin-octagram.deb --preset ice
```

脚本只通过 `sudo` 安装 APT 软件包和 deb；用户目录中的 Rime 配置始终以当前桌面用户身份修改。

## 使用预编译 deb

Release 提供四个与 Ubuntu 22.04 同名、职责相同但版本更高的软件包：

```text
librime1
librime-bin
librime-plugin-lua
librime-plugin-octagram
```

把四个 deb 放在同一目录后执行：

```bash
sudo apt install ./*.deb
```

APT 会把它们视为 Jammy 对应软件包的升级版本。它们不依赖 Fcitx5/IBus，不安装用户配置脚本，也不会激活输入法。根据桌面环境另外安装 Ubuntu 官方前端：

```bash
sudo apt install fcitx5-rime
# 或
sudo apt install ibus-rime
```

如需安装雾凇并设置输入法，请克隆本仓库后显式运行：

```bash
scripts/install-rime-ice.sh
# 或
scripts/install-rime-ice.sh --frontend ibus
```

只安装方案、不修改当前输入法：

```bash
scripts/install-rime-ice.sh --no-activate
```

软件包使用 Ubuntu 标准路径：

```text
/usr/lib/x86_64-linux-gnu/librime.so.1
/usr/lib/x86_64-linux-gnu/rime-plugins/librime-lua.so
/usr/lib/x86_64-linux-gnu/rime-plugins/librime-octagram.so
/usr/bin/rime_deployer
```

这些文件都由 `dpkg` 记录所有权。`apt update` 和 `apt upgrade` 会正常工作，并且不会因为 Jammy 仓库中的 1.7.3 版本较旧而自动降级。

## 安装职责

完整的 Fcitx5 雾凇安装由三部分组成：

1. **Ubuntu APT**：安装 `fcitx5-rime` 或 `ibus-rime` 输入法前端，以及 Boost、ICU、glibc 等动态依赖。
2. **rime-ready 生成的标准 deb**：以更高版本升级 Ubuntu 的 `librime1`、`librime-bin`、`librime-plugin-lua` 和 `librime-plugin-octagram`，使用 `/usr/lib`、`/usr/bin` 等标准路径。deb 不包含用户配置脚本，也不激活输入法。
3. **仓库脚本**：下载和校验四个 deb，选择输入法前端，安装稳定版雾凇或万象 Gram，编译用户方案，并在用户明确选择时修改 Fcitx5/IBus 配置和启动前端。

需要回退时，`scripts/uninstall.sh` 会使用 `apt --allow-downgrades` 恢复 Ubuntu 22.04 官方版本，而不是手工删除库文件。

## 分步构建

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

强制清理并重新构建：

```bash
scripts/build.sh --target ubuntu-22.04 --clean
```

发布前的完整检查统一由 CT 脚本执行：

```bash
scripts/ct.sh --target ubuntu-22.04
```

本地可使用预装好 APT 依赖的复用容器，避免每次从 `ubuntu:22.04` 重新准备环境：

```bash
scripts/docker-ct.sh --target ubuntu-22.04
scripts/docker-ct.sh --reuse-build       # 复用已有编译目录
scripts/docker-ct.sh --rebuild-image     # 仅在基础依赖变化时重建镜像
```

默认镜像名为 `rime-ready-ubuntu22-ct:local`，可通过 `RIME_READY_CT_IMAGE` 覆盖。

CT 会编译固定版本的上游源码，运行 librime 单元测试，检查动态库依赖，生成四个标准 deb，并以 Lintian error 作为失败条件。随后安装 Ubuntu APT 的 `fcitx5-rime` 和 `ibus-rime`，通过 `ldd -r` 验证它们加载 `/usr/lib/x86_64-linux-gnu/librime.so.1` 时没有缺失库或未解析符号。最后，CT 用外部脚本部署稳定版雾凇，并编译一个小型 Rime API 测试应用：模拟输入 `nihao`，断言候选包含“你好”，选择候选后断言提交文本也是“你好”。Release Workflow 只有在这些检查全部通过后才会发布产物。

## 只安装或更新雾凇拼音

Fcitx5：

```bash
scripts/install-rime-ice.sh
```

IBus：

```bash
scripts/install-rime-ice.sh --frontend ibus
```

安装前，脚本会把原配置目录重命名为带时间戳的备份目录。更新雾凇时会保留已有的 `rime_ice.userdb`。

也可以只设置输入法前端，不重新安装方案：

```bash
scripts/configure-input-method.sh --frontend fcitx5
# 或
scripts/configure-input-method.sh --frontend ibus
```

## GitHub Actions

- `build.yml`：普通 `main` Push 会运行 CT；PR 不自动运行。需要测试 PR 时，在 Actions 页面手动运行 `Continuous test` 并填写 PR 编号。该 Workflow 只上传 CI 产物，永不发布版本。
- `release.yml`：推送 `v*` Tag 或在 Actions 页面手动触发时运行完整 CT，全部通过后发布四个 deb 和校验文件。
- `upstream-watch.yml`：每周一轮询稳定上游 Release。发现新版后直接更新 `main` 的固定版本并调度 `release.yml`，不创建 PR。Release Workflow 仍需完整 CT 通过才会发布。

手动触发 Release 时可以不填写 Tag。Workflow 会按以下格式自动生成：

```text
v<RIME_VERSION>-r<PACKAGE_REVISION>
```

例如：

```text
v1.17.0-r1
```

如果自动生成的 Tag 已存在，需要更新 `PACKAGE_REVISION`，或者手动填写另一个以 `v` 开头的 Tag。

工作流使用 Matrix 描述目标平台。目前只有：

```yaml
- target: ubuntu-22.04
  runner: ubuntu-22.04
```

增加新系统时，需要新增 `platforms/<target>/`，再把目标加入 Matrix。平台差异留在平台目录，通用的下载、编译、测试和打包流程继续使用 `scripts/`。

### 上游版本记录

仓库使用两个文件记录上游状态：

- `versions.env`：下一次构建使用的 librime Release、插件提交，以及雾凇 `full.zip` 的 Asset ID 和 SHA-256。
- `upstream-state.json`：最近一次成功发布的 rime-ready Release 实际包含的上游版本。稳定版雾凇还会记录压缩包 Asset ID 和 SHA-256。

自动轮询只跟踪 librime 的正式 Release，以及雾凇形如 `YYYY.MM.DD` 的稳定 Release。`librime-lua` 和 `librime-octagram` 没有稳定 Release/稳定分支，因此只固定已验证提交，不自动跟踪它们的 `master`。

每周轮询以 `upstream-state.json` 为基准。发现新版本后会更新 `versions.env` 并调度 Release Workflow；只有完整 CT 通过后才发布。Release 发布成功后，Workflow 才把本次发布信息写回 `upstream-state.json`；如果构建、输入输出测试或发布失败，成功状态不会提前更新。

也可以在 Actions 页面手动运行 `Watch upstream releases`，立即检查上游。

周期更新和 Release Workflow 需要仓库的 Actions 权限允许写入 Contents 和调度 Workflow。如果启用了 `main` 分支保护，需要允许它们更新 `versions.env` 和 `upstream-state.json`。

## 卸载

恢复 Ubuntu 22.04 官方 Rime 软件包：

```bash
scripts/uninstall.sh
```

恢复系统运行库不会删除 `~/.local/share/fcitx5/rime` 中的输入方案和用户词库。

## 说明

Ubuntu 22.04 自带 librime 1.7.3。新版雾凇使用的新式 Lua 模块加载方式无法在该版本正常运行，因此本项目成套构建 librime、librime-lua 和 librime-octagram，避免混用不匹配的 ABI。

项目生成的 deb 会通过 APT 正常升级 `/usr/lib/x86_64-linux-gnu` 和 `/usr/bin` 中对应软件包的文件；不会绕过 `dpkg` 手工覆盖这些路径。
