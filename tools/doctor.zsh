#!/usr/bin/env zsh
# 体检：不依赖 zpty，只检查插件本身能不能跑起来。
# 端到端测试在别人机器上卡住时，先跑这个确认是插件的问题还是测试
# 环境的问题。
#
#   zsh tools/doctor.zsh

emulate -L zsh
zmodload zsh/datetime

local ZPT_ROOT=${0:A:h:h}
local -i bad=0
_ok()   { printf '  \033[32m✓\033[0m %s\n' "$1" }
_warn() { printf '  \033[33m!\033[0m %s\n' "$1" }
_bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; (( bad++ )) }

print "环境"
_ok "zsh $ZSH_VERSION"
if [[ ${LC_ALL:-${LC_CTYPE:-$LANG}} == *(UTF-8|utf8)* ]]; then
  _ok "locale ${LC_ALL:-${LC_CTYPE:-$LANG}}"
else
  _bad "locale 不是 UTF-8（${LC_ALL:-${LC_CTYPE:-$LANG}}），中文目录名会被当成一堆乱码字节"
fi
if zmodload zsh/zpty 2>/dev/null; then
  _ok "zsh/zpty 可用（端到端测试需要）"
else
  _warn "没有 zsh/zpty，tools/test_complete.zsh 跑不了，不影响插件本身"
fi

print "\n插件"
ZPT_CACHE_DIR=${TMPDIR:-/tmp}/zpt-doctor.$$
source $ZPT_ROOT/zsh-pinyin-tab.plugin.zsh 2>/dev/null \
  && _ok "入口加载成功，ZPT_DIR=$ZPT_DIR" \
  || _bad "入口加载失败"

local -F t0=$EPOCHREALTIME
if _zpt_load_dict; then
  local -F ms=$(( ($EPOCHREALTIME - t0) * 1000 ))
  if (( ms > 50 )); then
    _warn "词表加载 ${ms%%.*} ms —— 偏慢，说明用的是没编译的 .zsh；正常应该 10ms 以内"
    _warn "  data/ 目录不可写的话插件编不出 .zwc，检查一下权限"
  else
    _ok "词表加载 ${ms%%.*} ms，${#_zpt_dict} 个字"
  fi
else
  _bad "词表加载失败"
fi

print "\n匹配"
local -a probes=( 'wd|文档' 'wendang|文档' 'wend|文档' 'xxbj|学习笔记' 'wdp|我的Projects' )
local p q n
for p in $probes; do
  q=${p%%|*}; n=${p##*|}
  if _zpt_match $q $n; then _ok "$q → $n"; else _bad "$q 匹配不上 $n"; fi
done

print "\n注册"
if (( $+functions[compdef] )); then
  _ok "compdef 可用"
else
  _warn "当前是非交互式 shell，compdef 不存在，注册会推迟到第一个 precmd（这在真实 shell 里是正常的）"
fi
print "  ZPT_COMMANDS = ${ZPT_COMMANDS[*]}"

rm -rf $ZPT_CACHE_DIR
print
if (( bad )); then
  printf '\033[31m%d 项有问题\033[0m\n' $bad
  return 1
else
  printf '\033[32m插件本身没问题\033[0m\n'
  print "如果实际用起来 Tab 没反应，检查 ~/.zshrc 里的 source 行是不是在 compinit 之后被别的东西覆盖了。"
fi
