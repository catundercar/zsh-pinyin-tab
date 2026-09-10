#!/usr/bin/env zsh
# 延迟基准。目标是单次补全 20ms 以内——超过这个数，Tab 会明显发黏。
#
#   zsh tools/bench.zsh [目录数]

emulate -L zsh
zmodload zsh/datetime

local ZPT_ROOT=${0:A:h:h}
local -i N=${1:-500}

ZPT_DIR=$ZPT_ROOT
fpath=( $ZPT_ROOT/functions $fpath )
typeset -gA _zpt_dict
typeset -gA _zpt_syl _zpt_ini _zpt_ful _zpt_first
typeset -ga _zpt_toks _zpt_opt
typeset -g _zpt_pinyin
typeset -gi _zpt_dirty=0 _zpt_dict_loaded=0
autoload -Uz _zpt_load_dict _zpt_index _zpt_syllables _zpt_match _zpt_pinyin_of _zpt_filter
typeset -ga _zpt_names _zpt_hits _zpt_disp
typeset -gi ZPT_SHOW_PINYIN=1

# 造一批像样的中文目录名
local -a w1=(项目 文档 我的 公司 个人 学习 工作 临时 归档 客户 产品 设计 测试 运维 财务)
local -a w2=(资料 笔记 备份 报告 计划 记录 方案 素材 归档 附件 数据 图纸 合同 周报 存档)
local -a names=()
local -i i
for (( i = 0; i < N; i++ )); do
  case $(( i % 5 )) in
    0) names+=( "${w1[RANDOM%$#w1+1]}${w2[RANDOM%$#w2+1]}" ) ;;
    1) names+=( "${w1[RANDOM%$#w1+1]}${w2[RANDOM%$#w2+1]}$i" ) ;;
    2) names+=( "${w1[RANDOM%$#w1+1]}-${w2[RANDOM%$#w2+1]}" ) ;;
    3) names+=( "${w1[RANDOM%$#w1+1]}Project$i" ) ;;
    *) names+=( "proj-$i" ) ;;
  esac
done

local -a queries=( wd xm gzjl grbj xuexi wendang gsbf ceshi )

# 跑一轮：对每个 query 扫一遍全部目录名，模拟一次补全的匹配开销
# 走和真实补全完全一样的路径
_one() { _zpt_filter $1 }

_zpt_names=( $names )
print "目录数 $N，查询 $#queries 个\n"

local t0 ms
local -a samples

t0=$EPOCHREALTIME; _zpt_load_dict
printf '  %-30s %7.1f ms   一个 shell 只付一次\n' '词表加载' $(( ($EPOCHREALTIME-t0)*1000 ))

# 首次 Tab：这个目录下 N 个名字全都没建过索引
_zpt_syl=(); _zpt_ini=(); _zpt_ful=(); _zpt_first=()
t0=$EPOCHREALTIME; _one $queries[1]
printf '  %-30s %7.1f ms   %d 个名字全部要建索引\n' '首次进入该目录的第一次 Tab' $(( ($EPOCHREALTIME-t0)*1000 )) $N

# 后续 Tab：索引已在内存里
samples=()
local q
for q in $queries; do
  t0=$EPOCHREALTIME; _one $q; samples+=( $(( ($EPOCHREALTIME-t0)*1000 )) )
done
for q in $queries; do
  t0=$EPOCHREALTIME; _one $q; samples+=( $(( ($EPOCHREALTIME-t0)*1000 )) )
done
local -a sorted=( ${(n)samples} )
printf '  %-30s p50 %.1f ms / p95 %.1f ms / max %.1f ms\n' '之后每次 Tab' \
  $sorted[$(( ($#sorted+1)/2 ))] $sorted[$(( ($#sorted*95+99)/100 ))] $sorted[-1]

print
printf '  索引缓存 %d 条\n' $#_zpt_syl
printf '  目标是每次 Tab 20ms 以内——超过这个数，Tab 会明显发黏\n'
