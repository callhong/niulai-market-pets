#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
NIULAI_SKIP_BUILD=1 \
NIULAI_APP_SOURCE="$script_dir/NiuLaiMarketPets.app" \
  "$script_dir/scripts/install.sh"

print "安装完成。控制器已启动；按回车关闭此窗口。"
read
