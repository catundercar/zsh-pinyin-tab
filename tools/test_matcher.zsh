#!/usr/bin/env zsh
# matcher-list 回归测试。
#
# 盯的是一个曾经很隐蔽的 bug：_zpt_complete 的返回值会决定
# _main_complete 还跑不跑后面几轮 matcher。
#
# 很多人的配置是「先精确匹配，配不上再忽略大小写」：
#
#     zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'
#
# 旧代码直接 return 了拼音那一步的结果。拼音一旦命中就返回 0，
# _main_complete 当场 break，第二轮（忽略大小写）永远轮不到——
# 目录里同时有 Work 和 我的 时，cd wo<Tab> 只剩「我的」，Work 消失。
# 反过来拼音没命中、原生命中了却返回 1，又会让它白跑后面几轮子串
# matcher，候选里混进一堆不该有的东西。
#
# 这里用 menu_complete + 连按 Tab 把候选一个个换出来，直接看
# 「用户能不能按到 Work」，不去解析屏幕输出也不看内部返回值。
#
#   zsh tools/test_matcher.zsh

emulate -L zsh
setopt extended_glob
zmodload zsh/datetime

: ${ZPT_TEST_TIMEOUT:=5}

local ZPT_ROOT=${0:A:h:h}
local WORK=${${TMPDIR:-/tmp}%/}/zpt-matcher.$$.$RANDOM
local RC=$WORK/rc PLAY=$WORK/play OUT=$WORK/out.txt

# 子 shell 退出时 _zpt_flush_cache 是 &! 起的后台任务，可能比 trap 还晚
# 往 $WORK/cache 里写。一次 rm 撞上正在写的目录会报 Directory not empty，
# 所以退一步再删一次。
_cleanup() { rm -rf $WORK 2>/dev/null || { sleep 0.2; rm -rf $WORK 2>/dev/null }; }
trap _cleanup EXIT
rm -rf $WORK
mkdir -p $RC $PLAY

# Work/我的 和 WenDang/文档 是两对「原生靠忽略大小写才配得上、
# 同时又有拼音候选」的组合，正是旧代码丢候选的地方
mkdir -p $PLAY/{Work,我的,WenDang,文档,Notes}

cat > $RC/.zshrc <<RCEOF
export LANG=C.UTF-8 LC_ALL=C.UTF-8
ZPT_CACHE_DIR=$WORK/cache
autoload -Uz compinit && compinit -u -d $WORK/zcompdump
# 第一轮精确、第二轮忽略大小写——本测试的全部意义所在
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'
source $ZPT_ROOT/zsh-pinyin-tab.plugin.zsh
# 每按一次 Tab 就换下一个候选，好把候选表整个转一遍
setopt menu_complete
PROMPT='@@ '; RPROMPT=''; setopt no_beep
# 用 widget 把当前命令行落盘。屏幕输出里混着按键回显和 zle 重绘，
# 不能拿来当依据
_zpt_dump() { print -r -- "\$BUFFER" >> $OUT; zle send-break }
zle -N _zpt_dump
bindkey '^G' _zpt_dump
cd $PLAY
RCEOF

zmodload zsh/zpty 2>/dev/null || { print -u2 "没有 zsh/zpty 模块，跳过"; return 0 }
zpty -b Z "HOME=$WORK ZDOTDIR=$RC TERM=vt100 zsh -d -i"

local _acc _transcript=""
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
  zpty -d Z 2>/dev/null
  return 1
}

_wait_prompt || return $(_bail "子 shell 起来之后没等到第一个提示符")
zpty -wn Z $'\r'; sleep 0.15
_wait_prompt || return $(_bail "空跑一条命令之后没等到提示符")

# 名称|敲什么|必须能按到的候选（空格分隔）
local -a cases=(
  '忽略大小写的候选不能被拼音挤掉|cd wo|Work 我的'
  '全拼也一样|cd wendang|WenDang 文档'
  '纯拼音查询照常工作|cd wd|我的 文档'
  '纯英文查询不受影响|cd not|Notes'
)

# 连按 4 次 Tab，把能换出来的候选都收集起来
local -i TABS=4
local -i k j
local c name keys want tabs line
local -A collected

for c in $cases; do
  name=${c%%|*}; keys=${${c#*|}%|*}; want=${c##*|}
  printf '  ... %-44s\r' $name
  for (( k = 1; k <= TABS; k++ )); do
    tabs=""
    for (( j = 0; j < k; j++ )); do tabs+=$'\t'; done
    _drain
    zpty -wn Z "$keys$tabs"; sleep 0.45; _drain
    zpty -wn Z $'\a'          # ^G：把命令行落盘
    sleep 0.2; _drain
    zpty -wn Z $'\003'        # ^C：清掉这一行
    sleep 0.1; _drain
  done
  print -r -- "###$name" >> $OUT
done
printf '%-46s\r' ''

zpty -d Z

# 按用例把收集到的命令行切开
local cur=""
for line in ${(f)"$(<$OUT)"}; do
  if [[ $line == '###'* ]]; then
    collected[${line#\#\#\#}]=$cur; cur=""
  else
    cur+="$line"$'\n'
  fi
done

local -i pass=0 fail=0
local body w
local -a missing
for c in $cases; do
  name=${c%%|*}; keys=${${c#*|}%|*}; want=${c##*|}
  body=${collected[$name]}
  missing=()
  for w in ${=want}; do
    # 命令行长这样：cd Work/ 或 cd 我的/
    [[ $body == *"${keys%% *} "*"$w"* ]] || missing+=( $w )
  done
  if (( $#missing )); then
    (( ++fail ))
    printf '  \033[31mFAIL\033[0m  %-32s 按不到 %s\n' $name "${missing[*]}"
    printf '        实际能按到：%s\n' "${${body//$'\n'/ }## #}"
  else
    (( ++pass ))
    printf '  \033[32mok\033[0m    %-32s -> %s\n' $name "$want"
  fi
done

print
if (( fail )); then
  printf '\033[31m%d 通过, %d 失败\033[0m\n' $pass $fail; return 1
else
  printf '\033[32m全部 %d 条通过\033[0m\n' $pass
fi
