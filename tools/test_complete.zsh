#!/usr/bin/env zsh
# 端到端补全测试。用 zsh/zpty 起一个真正的交互式 zsh，敲 Tab、回车，
# 然后让它把 $PWD 写到文件里——验证的是「最终插进命令行的到底是
# 什么」，而不只是匹配函数的返回值。
#
# 别去解析 pty 的屏幕输出：里面混着按键回显和 zle 重绘，看起来像
# "cd wd文档/" 这种东西，其实命令行里是对的，纯属自己吓自己。
#
#   zsh tools/test_complete.zsh

emulate -L zsh
setopt extended_glob
zmodload zsh/datetime

# 单步等提示符的上限（秒）。调大它不会让卡住的用例变好，只会让你多等
: ${ZPT_TEST_TIMEOUT:=5}

local ZPT_ROOT=${0:A:h:h}
local WORK=${${TMPDIR:-/tmp}%/}/zpt-e2e.$$.$RANDOM
local RC=$WORK/rc PLAY=$WORK/play OUT=$WORK/out.txt

# 子 shell 退出时 _zpt_flush_cache 是 &! 起的后台任务，可能比 trap 还晚
# 往 $WORK/cache 里写。一次 rm 撞上正在写的目录会报 Directory not empty，
# 所以退一步再删一次。
_cleanup() { rm -rf $WORK 2>/dev/null || { sleep 0.2; rm -rf $WORK 2>/dev/null }; }
trap _cleanup EXIT
rm -rf $WORK
mkdir -p $RC $PLAY

mkdir -p $PLAY/{文档,下载,项目,我的Projects,work,my-docs,学习笔记}
mkdir -p $PLAY/sub/文档
mkdir -p "$PLAY/我的 归档"

cat > $RC/.zshrc <<RCEOF
export LANG=C.UTF-8 LC_ALL=C.UTF-8
ZPT_CACHE_DIR=$WORK/cache
autoload -Uz compinit && compinit -u -d $WORK/zcompdump
source $ZPT_ROOT/zsh-pinyin-tab.plugin.zsh
PROMPT='@@ '; RPROMPT=''; setopt no_beep
cd $PLAY
RCEOF

zmodload zsh/zpty 2>/dev/null || { print -u2 "没有 zsh/zpty 模块，跳过端到端测试"; return 0 }
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
# 先空跑一条命令，确认 shell 真的在等输入了再开始。少了这一步，
# 第一条用例会在 compinit 还没收尾时抢跑。
_enter || return $(_bail "空跑一条命令之后没等到提示符")

# 名称 按键(含\t) 期望落点
local -a cases=(
  '首字母唯一命中|xz\t|下载'
  # wd 同时命中 文档 / 我的Projects。曾经在这里丢过输入：-U 让补全
  # 系统去插「公共前缀」，两个中文候选的公共前缀是空串，cd wd 被抹成
  # cd。现在强制菜单插入，第一次 Tab 应该直接给出第一个候选。
  '多候选走菜单(按拼音排序)|wd\t|文档'
  '多候选按两次 Tab|wd\t\t|我的 归档'
  # 单个字母不该被拼音淹掉，应该老老实实走原生
  '单字母走原生|w\t|work'
  '全拼|wendang\t|文档'
  '半截拼音|wend\t|文档'
  '四字首字母|xxbj\t|学习笔记'
  '带目录前缀(验证 -p)|sub/wd\t|sub/文档'
  '名字里有空格|wdgd\t|我的 归档'
  '中英混排|wdp\t|我的Projects'
  'ASCII 段全拼|wdprojects\t|我的Projects'
  '纯 ASCII 走原生|wor\t|work'
  '跳过连字符|myd\t|my-docs'
  '纯 ASCII 前缀仍归原生|my\t|my-docs'
)

local c name keys want
for c in $cases; do
  name=${c%%|*}; keys=${${c#*|}%|*}; want=${c##*|}
  printf '  ... %-44s\r' $name
  _type "cd ${(g::)keys}"
  _enter || return $(_bail "用例「$name」敲完回车后没等到提示符")
  _type "print -r -- \"${name}|${want}|\$PWD\" >> $OUT"
  _enter
  _type "cd $PLAY"
  _enter || return $(_bail "用例「$name」之后回演练场没等到提示符")
done
printf '%-40s\r' ''

zpty -d Z

local -i pass=0 fail=0
local line got expect
for line in ${(f)"$(<$OUT)"}; do
  name=${line%%|*}; line=${line#*|}
  want=${line%%|*}; got=${line#*|}
  # '!' 表示这一条不该补出任何东西，光标应该还留在演练场根目录
  expect=$PLAY; [[ $want != '!' ]] && expect=$PLAY/$want
  if [[ $got == $expect ]]; then
    (( ++pass )); printf '  \033[32mok\033[0m    %-22s -> %s\n' $name "${got#$PLAY/}"
  else
    (( ++fail )); printf '  \033[31mFAIL\033[0m  %-22s 期望 %s 实际 %s\n' $name "$expect" "$got"
  fi
done

print
if (( fail )); then
  printf '\033[31m%d 通过, %d 失败\033[0m\n' $pass $fail; return 1
else
  printf '\033[32m全部 %d 条通过\033[0m\n' $pass
fi
