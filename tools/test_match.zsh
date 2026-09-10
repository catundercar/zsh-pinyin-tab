#!/usr/bin/env zsh
# 匹配层的单元测试。纯函数级，不依赖交互式补全。
#   zsh tools/test_match.zsh

# 注意：不能开 err_return。这份代码里到处是 (( ... )) 当布尔用，
# 而算术表达式求值为 0 时退出码是 1，err_return 会把函数从中间掐断。
emulate -L zsh

ZPT_DIR=${0:A:h:h}
fpath=( $ZPT_DIR/functions $fpath )
typeset -gA _zpt_dict
typeset -gA _zpt_syl _zpt_ini _zpt_ful _zpt_first
typeset -ga _zpt_toks _zpt_opt
typeset -g _zpt_pinyin
typeset -gi _zpt_dirty=0 _zpt_dict_loaded=0
autoload -Uz _zpt_load_dict _zpt_index _zpt_syllables _zpt_match _zpt_pinyin_of

# 查询|目录名|期望(hit/miss)|说明
# 用 | 分隔而不是空格，因为目录名本身可能带空格
local -a cases=(
  # 首字母
  'wd|文档|hit|首字母'
  'xm|项目|hit|首字母'
  'wdgz|我的工作|hit|四字首字母'
  # 全拼
  'wendang|文档|hit|全拼'
  'xiangmu|项目|hit|全拼'
  'zhongwen|中文|hit|全拼'
  # 半截拼音（这是必须上 DP 的原因）
  'wend|文档|hit|前一个字全拼+后一个字首字母'
  'wdang|文档|hit|前首字母+后全拼'
  'xiangm|项目|hit|半截结尾'
  'zhw|中文|hit|zh 前缀顺带覆盖了双字母首字母'
  # 前缀匹配：目录名不必被消耗完
  'wd|文档备份|hit|前缀'
  'wdbf|文档备份|hit|全首字母'
  # 多音字
  'cw|重文|hit|重=chong'
  'zw|重文|hit|重=zhong'
  'xz|行政|hit|行=xing'
  'hz|行政|hit|行=hang'
  # 中英混排
  'wdp|我的Projects|hit|ASCII 段当一个 token'
  'wdproj|我的Projects|hit|ASCII 段前缀'
  'wdprojects|我的Projects|hit|ASCII 段全长'
  # 分隔符可跳过。序列化时分隔符存成「1+分隔符」，连续分隔符最容易
  # 把 toks/opt 的下标错开，下面三条盯的就是这个
  'myd|my-docs|hit|跳过连字符'
  'mydocs|my-docs|hit|跳过连字符+全拼'
  'wdwd|我的_文档|hit|跳过下划线'
  'wdgd|我的  归档|hit|连续两个空格'
  'wd|文档 |hit|结尾带空格'
  'wdxm|我的-_-项目|hit|一串混合分隔符'
  # 纯 ASCII 只按前缀匹配，避免和原生补全重复
  'wo|work|hit|ASCII 前缀'
  'wk|work|miss|ASCII 不做首字母'
  # 否定用例
  'wa|文档|miss|第二个字对不上'
  'glxm|项目管理|miss|不支持乱序'
  'wgz|我的工作|miss|不支持跳字'
  'zzz|文档|miss|完全不沾边'
  'wdx|文档|miss|查询比目录长'
)

local pass=0 fail=0
local line q name want desc got
for line in $cases; do
  q=${line%%|*}; line=${line#*|}
  name=${line%%|*}; line=${line#*|}
  want=${line%%|*}; desc=${line#*|}
  if _zpt_match $q "$name"; then got=hit; else got=miss; fi
  if [[ $got == $want ]]; then
    (( pass++ ))
  else
    (( fail++ ))
    printf '  \033[31mFAIL\033[0m  %-11s %-14s 期望 %-4s 实际 %-4s  %s\n' $q "$name" $want $got $desc
  fi
done

print
_zpt_pinyin_of 我的Projects; printf '拼音展示: 我的Projects -> %s\n' $_zpt_pinyin
_zpt_pinyin_of 文档备份;      printf '拼音展示: 文档备份     -> %s\n' $_zpt_pinyin
print
if (( fail )); then
  printf '\033[31m%d 通过, %d 失败\033[0m\n' $pass $fail
  return 1
else
  printf '\033[32m全部 %d 条通过\033[0m\n' $pass
fi
