#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    print -u2 "用法: $0 <WindowLayoutTool.app> <输出.dmg> [卷标]"
    exit 64
fi

source_app="$1"
output_dmg="$2"
volume_name="${3:-Window Layout Tool}"

if [[ ! -d "$source_app" || "${source_app:e}" != "app" ]]; then
    print -u2 "找不到有效的 .app: $source_app"
    exit 66
fi

if [[ "${output_dmg:e}" != "dmg" ]]; then
    print -u2 "输出路径必须以 .dmg 结尾: $output_dmg"
    exit 64
fi

staging_dir="$(mktemp -d /tmp/window-layout-dmg.XXXXXX)"
cleanup() {
    rm -rf -- "$staging_dir"
}
trap cleanup EXIT INT TERM

ditto "$source_app" "$staging_dir/WindowLayoutTool.app"
ln -s /Applications "$staging_dir/Applications"

mkdir -p "${output_dmg:h}"
hdiutil create \
    -volname "$volume_name" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$output_dmg"

print "已创建: $output_dmg"
