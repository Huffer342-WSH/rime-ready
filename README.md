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

目前只支持 Ubuntu 22.04 amd64。克隆仓库后，以普通桌面用户运行：

```bash
./install.sh
```

同时安装万象语法模型：

```bash
./install.sh --with-gram
```

脚本会依次执行：

1. 安装编译依赖；
2. 编译 librime、Lua 和 Octagram；
3. 生成并安装 deb；
4. 安装雾凇拼音到当前用户的 Fcitx5 Rime 目录；
5. 编译方案并启动 Fcitx5。

脚本需要通过 `sudo` 安装系统依赖和 deb，但不会用 root 身份修改用户的 Rime 配置。

## 使用预编译 deb

从 GitHub Release 下载适用于 Ubuntu 22.04 的 deb，然后执行：

```bash
sudo apt install ./rime-ready_1.17.0-1~ubuntu22.04_amd64.deb
```

该 deb 只安装运行库、插件和命令行应用，不依赖 Fcitx5/IBus，不安装用户配置脚本，也不会激活输入法。根据桌面环境另外安装 Ubuntu 官方前端：

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

系统运行库安装在 `/usr/local`，不会覆盖 APT 在 `/usr/lib` 中管理的文件。动态链接器会优先选择：

```text
/usr/local/lib/librime.so.1
/usr/local/lib/rime-plugins/librime-lua.so
/usr/local/lib/rime-plugins/librime-octagram.so
```

## 分步构建

```bash
scripts/build.sh --target ubuntu-22.04
scripts/test-build.sh ubuntu-22.04
scripts/package-deb.sh --target ubuntu-22.04 --reuse-build
```

输出目录：

```text
dist/*.deb
dist/*.tar.gz
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

CT 会编译固定版本的上游源码，运行 librime 单元测试，检查动态库依赖，并生成 deb。随后安装 Ubuntu APT 的 `fcitx5-rime` 和 `ibus-rime`，通过 `ldd -r` 验证它们加载 `/usr/local/lib/librime.so.1` 时没有缺失库或未解析符号。最后，CT 用外部脚本部署稳定版雾凇，并编译一个小型 Rime API 测试应用：模拟输入 `nihao`，断言候选包含“你好”，选择候选后断言提交文本也是“你好”。Release Workflow 只有在这些检查全部通过后才会发布产物。

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

- `build.yml`：在每次 push、Pull Request 和手动触发时运行完整 CT，并上传测试通过的安装包。
- `release.yml`：推送 `v*` Tag 或在 Actions 页面手动触发时运行完整 CT，全部通过后发布 deb、tar.gz 和校验文件。
- `upstream-watch.yml`：每周一轮询一次上游；发现新版后更新固定版本、运行 CT，并创建或更新升级 PR。

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

每周轮询以 `upstream-state.json` 为基准。发现新版本后不会直接发布未经审查的安装包，而是先运行 CT 并创建升级 PR。Release 发布成功后，Workflow 才把本次发布信息写回 `upstream-state.json`；如果发布失败，记录不会提前更新。

也可以在 Actions 页面手动运行 `Watch upstream releases`，立即检查上游。

这些 Workflow 需要仓库的 Actions 权限允许写入 Contents 和创建 Pull Request。如果启用了 `main` 分支保护，需要允许 Release Workflow 写回 `upstream-state.json`，或者为该步骤配置具有相应权限的规则。

## 卸载

如果通过 deb 安装：

```bash
sudo apt remove rime-ready
```

源码安装产物也可以使用：

```bash
scripts/uninstall.sh
```

卸载系统运行库不会删除 `~/.local/share/fcitx5/rime` 中的输入方案和用户词库。

## 说明

Ubuntu 22.04 自带 librime 1.7.3。新版雾凇使用的新式 Lua 模块加载方式无法在该版本正常运行，因此本项目成套构建 librime、librime-lua 和 librime-octagram，避免混用不匹配的 ABI。

项目不会修改 `/usr/lib/x86_64-linux-gnu` 中由 APT 管理的文件。
