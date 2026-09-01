#!/usr/bin/env bash
# Check installer routing without invoking a package manager.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

write_os() {
  local name=$1
  shift
  printf '%s\n' "$@" >"$tmp/$name"
}

expect_route() {
  local name=$1 expected=$2 output
  output=$(RIME_READY_OS_RELEASE="$tmp/$name" "$PROJECT_ROOT/install.sh" --check-system)
  grep -Fq "$expected" <<<"$output" || {
    echo "$name 路由错误：$output" >&2
    exit 1
  }
}

expect_failure() {
  local name=$1
  if RIME_READY_OS_RELEASE="$tmp/$name" "$PROJECT_ROOT/install.sh" --check-system >/dev/null 2>&1; then
    echo "$name 应被拒绝" >&2
    exit 1
  fi
}

write_os ubuntu22 'ID=ubuntu' 'VERSION_ID="22.04"' 'PRETTY_NAME="Ubuntu 22.04"' 'VERSION_CODENAME=jammy'
write_os ubuntu24 'ID=ubuntu' 'VERSION_ID="24.04"' 'PRETTY_NAME="Ubuntu 24.04"' 'VERSION_CODENAME=noble'
write_os mint21 'ID=linuxmint' 'VERSION_ID="21.3"' 'PRETTY_NAME="Linux Mint 21.3"' 'UBUNTU_CODENAME=jammy'
write_os mint22 'ID=linuxmint' 'VERSION_ID="22.1"' 'PRETTY_NAME="Linux Mint 22.1"' 'UBUNTU_CODENAME=noble'
write_os fedora 'ID=fedora' 'VERSION_ID="43"' 'PRETTY_NAME="Fedora Linux 43"'
write_os arch 'ID=arch' 'PRETTY_NAME="Arch Linux"'
write_os cachyos 'ID=cachyos' 'ID_LIKE="arch"' 'PRETTY_NAME="CachyOS"'
write_os ubuntu20 'ID=ubuntu' 'VERSION_ID="20.04"' 'PRETTY_NAME="Ubuntu 20.04"' 'VERSION_CODENAME=focal'

expect_route ubuntu22 '包管理器：apt；Rime 来源：rime-ready'
expect_route ubuntu24 '包管理器：apt；Rime 来源：native'
expect_route mint21 '包管理器：apt；Rime 来源：rime-ready'
expect_route mint22 '包管理器：apt；Rime 来源：native'
expect_route fedora '包管理器：dnf；Rime 来源：native'
expect_route arch '包管理器：pacman；Rime 来源：native'
expect_route cachyos '包管理器：pacman；Rime 来源：native'
expect_failure ubuntu20

fake_bin="$tmp/bin"
command_log="$tmp/commands.log"
mkdir -p "$fake_bin"
cat >"$fake_bin/sudo" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$RIME_READY_COMMAND_LOG"
"$@"
SH
cat >"$fake_bin/apt-get" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$fake_bin/apt-cache" <<'SH'
#!/usr/bin/env bash
[[ $1 == show && $2 == librime1t64 ]]
SH
cat >"$fake_bin/dpkg-query" <<'SH'
#!/usr/bin/env bash
echo '1.10.0+dfsg1-1build2'
SH
cat >"$fake_bin/dnf" <<'SH'
#!/usr/bin/env bash
if [[ $* == *'list --available librime-octagram'* ]]; then exit 1; fi
exit 0
SH
cat >"$fake_bin/rpm" <<'SH'
#!/usr/bin/env bash
if [[ $* == *librime-octagram* ]]; then exit 1; fi
echo '1.17.0'
SH
cat >"$fake_bin/pacman" <<'SH'
#!/usr/bin/env bash
if [[ $1 == -Q ]]; then echo 'librime 1:1.17.0-5'; fi
SH
cat >"$fake_bin/rime_deployer" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fake_bin"/*

expect_install_command() {
  local name=$1 expected=$2
  : >"$command_log"
  PATH="$fake_bin:$PATH" \
    RIME_READY_COMMAND_LOG="$command_log" \
    RIME_READY_OS_RELEASE="$tmp/$name" \
    "$PROJECT_ROOT/install.sh" --preset runtime-only >/dev/null
  grep -Fq "$expected" "$command_log" || {
    echo "$name 未调用预期命令 $expected" >&2
    cat "$command_log" >&2
    exit 1
  }
}

expect_install_command ubuntu24 'apt-get install -y librime1t64 librime-bin librime-plugin-lua librime-plugin-octagram'
expect_install_command fedora 'dnf install -y librime librime-tools librime-lua'
expect_install_command arch 'pacman -Syu --needed --noconfirm librime'

if PATH="$fake_bin:$PATH" \
  RIME_READY_COMMAND_LOG="$command_log" \
  RIME_READY_OS_RELEASE="$tmp/fedora" \
  "$PROJECT_ROOT/install.sh" --preset ice-gram >/dev/null 2>&1; then
  echo '缺少 librime-octagram 时 Fedora ice-gram 应被拒绝' >&2
  exit 1
fi

echo '安装脚本系统识别、运行库路由和包管理器命令检查通过'
