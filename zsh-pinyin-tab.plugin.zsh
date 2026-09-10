# zsh-pinyin-tab —— 给 zsh 的补全加上拼音匹配
#
# 入口只做声明，不碰 IO 也不起子进程。词表和磁盘缓存都是懒加载。

# 拿到插件自身目录（$0 在被 source 时不可靠，这是社区通用写法）
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"
typeset -g ZPT_DIR="${0:A:h}"

# 老名字兼容：工具从 zsh-pinyin-cd 改名成 zsh-pinyin-tab，配置前缀跟着
# 从 ZPC_ 换成 ZPT_。已经在 .zshrc 里写了 ZPC_* 的人不该因为改名而
# 配置失效，所以这里把设过的老变量搬到新名字上。
{
  local _o _n
  for _o in MIN_CHARS MAX_ENTRIES SHOW_PINYIN FLUSH_THRESHOLD CACHE_DIR; do
    _n=ZPT_$_o
    (( $+parameters[ZPC_$_o] )) && (( ! $+parameters[$_n] )) && \
      typeset -g $_n="${(P)${:-ZPC_$_o}}"
  done
  if (( $+parameters[ZPC_COMMANDS] )) && (( ! $+parameters[ZPT_COMMANDS] )); then
    typeset -ga ZPT_COMMANDS
    ZPT_COMMANDS=( "${(@P)${:-ZPC_COMMANDS}}" )
  fi
} always { unset _o _n 2>/dev/null }

: ${ZPT_MIN_CHARS:=2}            # 少于这么多字母不介入
: ${ZPT_MAX_ENTRIES:=1000}       # 单目录超过这么多条目就退回原生
: ${ZPT_SHOW_PINYIN:=1}          # 候选后面显示拼音
: ${ZPT_FLUSH_THRESHOLD:=20}     # 新增多少条缓存后落盘
: ${ZPT_CACHE_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/zsh-pinyin-tab}

# 默认挂哪些命令。挑的都是「第一个参数就是路径」的命令——它们的补全
# 位置上冒出文件候选是对的。像 git / docker 这种先吃子命令的没放进来，
# 那种命令上插件分不清当前该补子命令还是补文件，见 README。
typeset -ga ZPT_COMMANDS ZPT_EXTRA_COMMANDS
(( $#ZPT_COMMANDS )) || ZPT_COMMANDS=(
  cd pushd popd                        # 目录
  ls ll la eza exa lsd                 # 列目录
  cat bat less more head tail          # 看内容
  vim nvim vi nano emacs code subl     # 编辑
  open xdg-open                        # 交给系统打开
  cp mv rm rmdir trash mkdir touch ln  # 文件操作
  stat file du dust df diff wc         # 信息
  chmod chown                          # 权限
  tar zip unzip gzip gunzip rsync scp  # 打包/传输
  source .                             # 加载脚本
)
# 想在默认表基础上再加几个，用这个，不必把整张表抄一遍
(( $#ZPT_EXTRA_COMMANDS )) && ZPT_COMMANDS+=( "${ZPT_EXTRA_COMMANDS[@]}" )
ZPT_COMMANDS=( ${(u)ZPT_COMMANDS} )

fpath=( "$ZPT_DIR/functions" "$ZPT_DIR/completions" $fpath )

typeset -gA _zpt_dict
typeset -gA _zpt_syl _zpt_ini _zpt_ful _zpt_first
typeset -gA _zpt_orig   # 命令 -> 它原本的补全函数
typeset -ga _zpt_toks _zpt_opt
typeset -g  _zpt_pinyin
typeset -gi _zpt_dirty=0 _zpt_dict_loaded=0

autoload -Uz _zpt_load_dict _zpt_index _zpt_syllables _zpt_match \
             _zpt_pinyin_of _zpt_filter _zpt_flush_cache _zpt_pinyin_matches \
             _zpt_complete

# 磁盘缓存只有几百条，加载很轻，直接读
[[ -r $ZPT_CACHE_DIR/names.zsh ]] && source $ZPT_CACHE_DIR/names.zsh

autoload -Uz add-zsh-hook
add-zsh-hook zshexit _zpt_flush_cache

# 注册前先把每个命令原本的补全函数记下来，_zpt_complete 跑的时候要
# 调它。没有原生补全的命令（_comps 里查不到）交给 _default，那本来
# 就是 zsh 对这类命令的默认行为。
_zpt_register() {
  local c orig
  for c in "${ZPT_COMMANDS[@]}"; do
    orig=${_comps[$c]}
    # 重复注册时别把原函数覆盖成我们自己
    [[ -n $orig && $orig != _zpt_complete ]] && _zpt_orig[$c]=$orig
    compdef _zpt_complete $c
  done
}

if (( $+functions[compdef] )); then
  _zpt_register
else
  # compinit 还没跑。挂到第一次 precmd——那时 compdef 一定已经存在，
  # 而且我们的注册排在所有 #compdef 扫描之后，结果是确定的。
  _zpt_deferred_register() {
    (( $+functions[compdef] )) && _zpt_register
    add-zsh-hook -d precmd _zpt_deferred_register
  }
  add-zsh-hook precmd _zpt_deferred_register
fi
