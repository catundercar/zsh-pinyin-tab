#!/usr/bin/env zsh
# 验证 ZPT_COMMANDS 挂到 cd 以外的命令上：
#   - 那个命令原本的补全不能被破坏
#   - 拼音候选要能补出文件，不只是目录
#   - 没有原生补全的命令（走 _default）也要能用
#
#   zsh tools/test_commands.zsh

emulate -L zsh
setopt extended_glob
zmodload zsh/datetime

# 单步等提示符的上限（秒）。调大它不会让卡住的用例变好，只会让你多等
: ${ZPT_TEST_TIMEOUT:=5}

local ZPT_ROOT=${0:A:h:h}
local WORK=${${TMPDIR:-/tmp}%/}/zpt-cmd.$$.$RANDOM
local RC=$WORK/rc PLAY=$WORK/play OUT=$WORK/out.txt

# 子 shell 退出时 _zpt_flush_cache 是 &! 起的后台任务，可能比 trap 还晚
# 往 $WORK/cache 里写。一次 rm 撞上正在写的目录会报 Directory not empty，
# 所以退一步再删一次。
_cleanup() { rm -rf $WORK 2>/dev/null || { sleep 0.2; rm -rf $WORK 2>/dev/null }; }
trap _cleanup EXIT
rm -rf $WORK
mkdir -p $RC $PLAY

mkdir -p $PLAY/{文档,项目}
: > $PLAY/报告.md
: > $PLAY/会议纪要.txt
: > $PLAY/report.txt
: > $PLAY/notes.md

cat > $RC/.zshrc <<RCEOF
export LANG=C.UTF-8 LC_ALL=C.UTF-8
ZPT_CACHE_DIR=$WORK/cache
ZPT_COMMANDS=(cd pushd ls probe)
autoload -Uz compinit && compinit -u -d $WORK/zcompdump
probe() { print -r -- "\$1" }
source $ZPT_ROOT/zsh-pinyin-tab.plugin.zsh
PROMPT='@@ '; RPROMPT=''; setopt no_beep
cd $PLAY
RCEOF

zmodload zsh/zpty 2>/dev/null || { print -u2 "没有 zsh/zpty 模块，跳过"; return 0 }
# -d 是 NO_GLOBAL_RCS：跳过 /etc/zshenv、/etc/zshrc 这些全局配置，只读
# 我们自己造的那份 rc。macOS 的 /etc/zshrc 会按 TERM_PROGRAM 再 source
# 一层终端相关的东西、挂 precmd 钩子、改提示符，测试环境不该受它影响。
zpty -b Z "HOME=$WORK ZDOTDIR=$RC TERM=vt100 zsh -d -i"

# 必须带 -n：zpty -w 默认会在字符串后面补一个换行，Tab 之后命令会被
# 直接执行掉，测出来的全是错位的结果。
#
# 敲键和回车要分开等：敲键（含 Tab）不会产生新提示符，去等提示符只
# 会白等满超时；只有回车执行完才会有新提示符。
#
# 每一步都有硬上限，任何情况下都不会卡死——等不到提示符就报出来，
# 顺便把子 shell 到目前为止吐的东西打出来，这比干等有用得多。
local _acc _transcript=""
local -F _deadline

_drain() { local c; local -i n=0; while (( n++ < 25 )); do
  if zpty -r Z c 2>/dev/null; then _transcript+=$c; else sleep 0.02; fi
done }

_wait_prompt() {
  local c; local -F t0=$EPOCHREALTIME
  _acc=""
  while (( EPOCHREALTIME - t0 < ZPT_TEST_TIMEOUT )); do
    if zpty -r Z c 2>/dev/null; then
      _acc+=$c; _transcript+=$c
      [[ $_acc == *'@@ '* ]] && { sleep 0.05
        while zpty -r Z c 2>/dev/null; do _acc+=$c; _transcript+=$c; done; return 0 }
    else
      sleep 0.02
    fi
  done
  return 1
}

_bail() {
  print -u2 "\n\033[31m卡住了\033[0m：$1"
  print -u2 "子 shell 到目前为止的原始输出（控制字符已替换）："
  print -u2 -r -- "  ${${${_transcript//$'\e'/<ESC>}//$'\r'/<CR>}//$'\n'/<LF>}"
  print -u2 "\n可能的原因："
  print -u2 "  · 提示符不是预期的 '@@ '（有全局 zsh 配置抢先改了 PROMPT？）"
  print -u2 "  · 子 shell 启动失败，上面的输出里应该有报错"
  zpty -d Z 2>/dev/null
  return 1
}

_type()  { _drain; zpty -wn Z "$1"; sleep 0.35; _drain }
_enter() { zpty -wn Z $'\r'; sleep 0.15; _wait_prompt }

_wait_prompt || return $(_bail "子 shell 起来之后没等到第一个提示符")
_enter || return $(_bail "空跑一条命令之后没等到提示符")

# 确认注册时真的把 ls 原本的补全函数存下来了，否则这组测试测不到东西
_type "print -r -- \"comps|\${_zpt_orig[ls]}\" >> $OUT"; _enter

# 名称|命令和按键|期望输出
local -a cases=(
  '原生补全没被破坏|ls rep\t|report.txt'
  '拼音补文件|ls bg\t|报告.md'
  '拼音补四字文件|ls hyjy\t|会议纪要.txt'
  '拼音补目录(带斜杠)|ls -d wd\t|文档/'
  '英文文件不受影响|ls not\t|notes.md'
  '没有原生补全的命令|probe wd\t|文档/'
)

local c name keys want
for c in $cases; do
  name=${c%%|*}; keys=${${c#*|}%|*}; want=${c##*|}
  printf '  ... %-44s\r' $name
  _type "${(g::)keys}"
  _type " >> $OUT"
  _enter || return $(_bail "用例「$name」敲完回车后没等到提示符")
done
printf '%-40s\r' ''

zpty -d Z

local -i pass=0 fail=0
local -a lines=( ${(f)"$(<$OUT)"} )
local comps=${lines[1]#comps|}
lines=( ${lines[2,-1]} )
if [[ -z $comps || $comps == _zpt_complete ]]; then
  print -u2 "  \033[31m注意\033[0m 没能存下 ls 的原生补全函数（拿到 [$comps]），下面的用例测不到东西"
else
  print "  已存下 ls 的原生补全函数: $comps"
fi

local -i i
for (( i = 1; i <= $#cases; i++ )); do
  name=${cases[i]%%|*}; want=${cases[i]##*|}
  local got=${lines[i]:-（无输出）}
  if [[ $got == $want ]]; then
    (( ++pass )); printf '  \033[32mok\033[0m    %-22s -> %s\n' $name "$got"
  else
    (( ++fail )); printf '  \033[31mFAIL\033[0m  %-22s 期望 %s 实际 %s\n' $name "$want" "$got"
  fi
done

print
if (( fail )); then
  printf '\033[31m%d 通过, %d 失败\033[0m\n' $pass $fail; return 1
else
  printf '\033[32m全部 %d 条通过\033[0m\n' $pass
fi
