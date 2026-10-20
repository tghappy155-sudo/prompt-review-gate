#!/usr/bin/env bash
# macOS / Linux / WSL; Bash 3.2+. No sudo or package installation.
set -euo pipefail

usage() {
  cat <<'HELP'
提示词优化助手安装器
用法：bash install.sh [--enable-default] [--source-dir DIR]
                       [--skills-dir DIR] [--codex-dir DIR]
  --enable-default  追加默认先优化、审核后执行规则（已有规则先备份）
  --source-dir DIR  从本地技能目录安装，跳过下载
  --skills-dir DIR  技能父目录，默认 ~/.agents/skills
  --codex-dir DIR   全局规则与备份目录，默认 CODEX_HOME 或 ~/.codex
  --help           显示帮助
HELP
}
fail() { printf '安装失败：%s\n' "$*" >&2; exit 1; }
need_arg() { [ "$#" -ge 2 ] && [ -n "$2" ] || fail "$1 需要目录参数"; }

skills_parent="${HOME:?无法确定用户目录}/.agents/skills"
codex_dir="${CODEX_HOME:-$HOME/.codex}"
source_dir=''
enable_default=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --enable-default) enable_default=1; shift ;;
    --source-dir) need_arg "$@"; source_dir="$2"; shift 2 ;;
    --skills-dir) need_arg "$@"; skills_parent="$2"; shift 2 ;;
    --codex-dir) need_arg "$@"; codex_dir="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "未知选项：$1" ;;
  esac
done

# Stage and validate downloads before touching an existing installation.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/prompt-review-gate.XXXXXXXX")
staged_skill=''
rollback_from=''
rollback_to=''
cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ -n "$rollback_from" ] && [ ! -e "$rollback_to" ]; then
    mv "$rollback_from" "$rollback_to" || true
  fi
  [ -z "$staged_skill" ] || rm -rf "$staged_skill"
  rm -rf "$work_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$work_dir/payload/agents"
if [ -n "$source_dir" ]; then
  [ -f "$source_dir/SKILL.md" ] && [ -f "$source_dir/agents/openai.yaml" ] || fail '本地来源缺少技能文件'
  cp "$source_dir/SKILL.md" "$work_dir/payload/SKILL.md"
  cp "$source_dir/agents/openai.yaml" "$work_dir/payload/agents/openai.yaml"
else
  command -v curl >/dev/null 2>&1 || fail '请先安装 curl，或使用 --source-dir 本地安装'
  base_url='https://raw.githubusercontent.com/tghappy155-sudo/prompt-review-gate/main'
  for file in SKILL.md agents/openai.yaml; do
    curl --fail --silent --show-error --location --connect-timeout 15 --max-time 60 \
      "$base_url/$file" -o "$work_dir/payload/$file" || fail '下载失败，已有安装未改动；请检查网络后重试'
  done
fi
grep -q '^name: prompt-review-gate' "$work_dir/payload/SKILL.md" || fail 'SKILL.md 内容不符合预期'
grep -q '^interface:' "$work_dir/payload/agents/openai.yaml" || fail '技能显示配置不符合预期'

# Prepare the optional global rule before replacing the installed skill.
agents_file="$codex_dir/AGENTS.md"
if [ -s "$codex_dir/AGENTS.override.md" ]; then
  agents_file="$codex_dir/AGENTS.override.md"
fi
rule_begin='<!-- prompt-review-gate:begin -->'
rule_end='<!-- prompt-review-gate:end -->'
cat > "$work_dir/rule" <<'RULE'
<!-- prompt-review-gate:begin -->
## 提示词优化助手：先优化，你确认，再执行

对新需求先使用 $prompt-review-gate，理解意图、消除上下文可解决的歧义、明确范围和交付标准，只展示一个简洁可执行的待审核提示词，不擅自扩展需求。审核前不开展原任务的搜索或外部操作，上级指令要求除外。用户确认后再执行；确认、修订、补充信息和已批准任务的继续执行按技能处理，不重复审核。遵从用户最新明确的跳过或关闭指示；不覆盖系统、开发者指令或权限边界。
<!-- prompt-review-gate:end -->
RULE
if [ "$enable_default" -eq 1 ]; then
  [ ! -e "$agents_file" ] || [ -f "$agents_file" ] || fail '全局规则路径不是普通文件'
  if [ -f "$agents_file" ] && grep -Fq "$rule_begin" "$agents_file"; then
    begins=$(grep -Fc "$rule_begin" "$agents_file")
    ends=$(grep -Fc "$rule_end" "$agents_file" || true)
    [ "$begins" = 1 ] && [ "$ends" = 1 ] || fail '全局规则中的安装标记不完整，请先手动检查'
    awk -v begin="$rule_begin" -v end="$rule_end" -v block="$work_dir/rule" '
      $0 == begin {if (seen || skip) exit 2; seen=1; skip=1; while ((getline line < block)>0) print line; close(block); next}
      $0 == end {if (!skip) exit 2; skip=0; next}
      !skip {print}
      END {if (skip || !seen) exit 2}
    ' "$agents_file" > "$work_dir/AGENTS.md" || fail '全局规则标记顺序异常，未修改文件'
  else
    if [ -f "$agents_file" ] && grep -Fq "$rule_end" "$agents_file"; then
      fail '全局规则中的安装标记不完整，请先手动检查'
    fi
    if [ -f "$agents_file" ]; then cat "$agents_file" > "$work_dir/AGENTS.md"; else : > "$work_dir/AGENTS.md"; fi
    if [ -s "$work_dir/AGENTS.md" ]; then printf '\n\n' >> "$work_dir/AGENTS.md"; fi
    cat "$work_dir/rule" >> "$work_dir/AGENTS.md"
  fi
fi

mkdir -p "$skills_parent"
target="$skills_parent/prompt-review-gate"
# Preserve an existing discovery symlink and update its real directory.
link_count=0
while [ -L "$target" ]; do
  link_count=$((link_count + 1))
  [ "$link_count" -le 40 ] || fail '技能链接存在循环'
  next_target=$(readlink "$target")
  case "$next_target" in
    /*) target="$next_target" ;;
    *) target="$(dirname "$target")/$next_target" ;;
  esac
done
[ ! -e "$target" ] || [ -d "$target" ] || fail '技能安装位置已被非目录文件占用'
mkdir -p "$(dirname "$target")"
staged_skill=$(mktemp -d "$(dirname "$target")/.prompt-review-gate-stage.XXXXXXXX")
cp -R "$work_dir/payload/." "$staged_skill/"
backup_dir=''
make_backup_dir() {
  if [ -z "$backup_dir" ]; then
    mkdir -p "$codex_dir/backups/prompt-review-gate"
    backup_dir=$(mktemp -d "$codex_dir/backups/prompt-review-gate/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
  fi
}
if [ -e "$target" ]; then
  make_backup_dir
  mv "$target" "$backup_dir/skill"
  rollback_from="$backup_dir/skill"
  rollback_to="$target"
fi
mv "$staged_skill" "$target"
staged_skill=''
rollback_from=''

if [ "$enable_default" -eq 1 ]; then
  mkdir -p "$codex_dir"
  if [ -f "$agents_file" ] && cmp -s "$agents_file" "$work_dir/AGENTS.md"; then
    printf '默认前置规则已启用，无需重复写入。\n'
  else
    if [ -f "$agents_file" ]; then
      make_backup_dir
      cp -p "$agents_file" "$backup_dir/$(basename "$agents_file")"
    fi
    # Copy through existing symlinks to preserve the user's configuration layout.
    cat "$work_dir/AGENTS.md" > "$agents_file"
    printf '已启用默认先优化、审核后执行：%s\n' "$agents_file"
  fi
fi
printf '安装成功：%s\n' "$target"
[ -z "$backup_dir" ] || printf '旧版备份：%s\n' "$backup_dir"
printf '在 Codex 中输入 $prompt-review-gate 即可调用；若未显示，请重启 Codex。\n'
if [ "$enable_default" -eq 0 ]; then
  printf '默认规则未改动。如需新需求先优化，重跑安装命令并加 --enable-default。\n'
fi
printf '此命令安装技能，不会安装 Codex 本身，也不自动同步到手机。\n'
