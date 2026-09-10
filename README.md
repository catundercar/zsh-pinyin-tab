# zsh-pinyin-tab

给 zsh 的补全加拼音匹配。`cd wd<Tab>` 补出 `文档`，`vim bg<Tab>` 补出 `报告.md`。

```
~/notes $ cd wd<Tab>
拼音匹配
文档  (wendang)      我的 归档  (wodeguidang)      我的Projects  (wodeprojects)
```

首字母、全拼、以及两者的混合都认：

| 敲 | 补出 |
|---|---|
| `wd` | 文档 |
| `wendang` | 文档 |
| `wend` | 文档 |
| `xxbj` | 学习笔记 |
| `wdp` | 我的Projects |
| `myd` | my-docs |

拼音候选是**加**在原生补全后面的，不是替换。原生补全该补出来的东西
（包括忽略大小写、部分词匹配那几轮 `matcher-list`）一个都不少。

## 安装

```zsh
# zinit
zinit light catundercar/zsh-pinyin-tab

# antidote / .zsh_plugins.txt
catundercar/zsh-pinyin-tab

# 手动
git clone https://github.com/catundercar/zsh-pinyin-tab ~/.zsh/zsh-pinyin-tab
echo 'source ~/.zsh/zsh-pinyin-tab/zsh-pinyin-tab.plugin.zsh' >> ~/.zshrc
```

仓库里带了 `install.zsh`，它会拷贝到 `~/.zsh/zsh-pinyin-tab` 并改好
`~/.zshrc`，从旧名字 `zsh-pinyin-cd` 升级上来也认。

在 `compinit` 之前或之后加载都行——插件会自己判断，必要时把注册推迟到
第一个 `precmd`。

需要 zsh 5.8+ 和 UTF-8 的 locale。

## 挂在哪些命令上

默认挂在一批「第一个参数就是路径」的命令上：

```
cd pushd popd
ls ll la eza exa lsd
cat bat less more head tail
vim nvim vi nano emacs code subl
open xdg-open
cp mv rm rmdir trash mkdir touch ln
stat file du dust df diff wc chmod chown
tar zip unzip gzip gunzip rsync scp
source .
```

想加几个：

```zsh
ZPT_EXTRA_COMMANDS=(z j mpv)
```

想完全自己定：

```zsh
ZPT_COMMANDS=(cd pushd vim)
```

注册时会先把每个命令原本的补全函数存下来，补全时先跑它、再补拼音候选，
所以那个命令原有的补全不受影响。没有原生补全的命令走 `_default`，那本来
就是 zsh 对这类命令的默认行为。

原生补全是 `_cd` 的（`cd`/`pushd`）只给目录；其余命令目录和文件都给，
所以 `vim bg<Tab>` 能补出 `报告.md`。

`git`、`docker` 这种先吃子命令的命令**没有**放进默认表。插件分不清当前
位置该补子命令还是补文件，挂上去的话 `git ch<Tab>` 除了 `checkout` 还会
冒出当前目录里拼音匹配 `ch` 的文件。真要加自己往 `ZPT_EXTRA_COMMANDS`
里放。

## 配置

写在 `source` 之前：

```zsh
ZPT_MIN_CHARS=2        # 少于这么多字母不介入。1 会让 cd w<Tab> 也弹一堆中文
ZPT_MAX_ENTRIES=1000   # 单目录条目数超过这个就退回原生补全
ZPT_SHOW_PINYIN=1      # 候选后面显示 (wendang)
ZPT_COMMANDS=(...)     # 完全覆盖默认命令表
ZPT_EXTRA_COMMANDS=()  # 在默认表基础上追加
ZPT_CACHE_DIR=~/.cache/zsh-pinyin-tab
ZPT_FLUSH_THRESHOLD=20 # 新增多少条索引后落盘
```

工具原来叫 `zsh-pinyin-cd`，配置前缀是 `ZPC_`。老前缀仍然认（入口处会
搬到新名字上），但建议改过来。

## 它怎么工作

四层，自底向上：

**词表**（`data/pinyin.zsh`）覆盖 CJK 基本区 20892 个字，多音字每字最多留
三个读音。由 `tools/gen_dict.py` 用 pypinyin 离线生成，你的机器上不需要
Python。词表是懒加载的，而且必须用 `zcompile` 过的 `.zwc`——原始 `.zsh`
解析要 210ms，`.zwc` 只要 6ms。`.zwc` 是二进制词码，跨机器带不保险，所以
不进仓库，插件第一次用到词表时自己编一份（需要 `data/` 可写）。

**索引**把目录名拆成读音序列，`我的_Projects` → `(wo)(de|di)[_](projects)`。
连续的 ASCII 字母数字合并成一个 token，分隔符标成可跳过。结果按名字
缓存（不是按路径——`文档`、`下载` 这类名字在不同地方反复出现，一次转换
处处受益），内存一份，磁盘一份。

**匹配**是个 DP，不是贪心。反例：输入 `wen` 配 `文档`，`w` 当首字母走不通
（剩下的 `en` 匹配不上 `dang`），必须 `wen` 整体消耗掉「文」才对。同一
位置上消耗 1 个字符和消耗 3 个字符都可能是正确分支，得同时留着。每个读音
允许消耗它的任意前缀，`k=1` 就是首字母、`k=|p|` 就是全拼，三种情况一条
规则覆盖。

真正跑 DP 的候选很少：先用「首字母集合」一次 glob 否掉九成以上，再用
首字母串/全拼串的前缀命中直接判正，剩下的才进 DP。

**补全集成**先跑这个命令原本的补全函数，再把拼音候选 `compadd -U` 进去。
顺序和返回值都有讲究，见下面。

## 实测延迟

500 个中文目录（aarch64 容器，比一般笔记本慢）：

```
词表加载                 7.0 ms   一个 shell 只付一次
首次进入该目录的第一次 Tab   34.4 ms   500 个名字全部要建索引
之后每次 Tab            p50 4.5 ms / p95 10.2 ms
```

1000 个目录时 p95 会到 17.5ms，正好贴着「Tab 开始发黏」的线，所以
`ZPT_MAX_ENTRIES` 默认就设在 1000。

## 踩过的坑

几条不写出来下次还会再踩的：

**补全函数的返回值决定 `matcher-list` 还跑不跑。** 这个最隐蔽。
`_main_complete` 会拿 `matcher-list` 里的每条 matcher 轮流跑一遍补全，
**只要某轮返回 0 就 break**。很多人的配置是「先精确匹配，配不上再忽略
大小写兜底」：

```zsh
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}'
```

早期版本在包装函数里直接 `return` 了拼音那一步的结果，两个方向都错：

- 拼音命中 → 返回 0 → 第一轮就 break，忽略大小写那轮永远轮不到。
  目录里同时有 `Work` 和 `我的` 时，`cd wo<Tab>` 只剩「我的」，`Work`
  凭空消失——「装了这插件就不能不区分大小写了」说的就是这个。
- 拼音没命中但原生命中了 → 返回 1 → `_main_complete` 以为这轮失败，
  继续往下试 `r:|=*` / `l:|=*` 那些子串 matcher。明明已经精确命中，
  候选里却混进一堆子串匹配。

正确的语义是「这一轮到底有没有产出候选」，也就是
`原生补全成功 || 拼音补全成功`。另外拼音候选只在「这轮原生成功」或
「这是最后一轮 matcher」时加——每轮都加会让热点函数白跑好几遍，只在
第一轮加又会在「第一轮没中、第二轮才中」时把拼音候选排到原生候选前面，
而敲 `cd w<Tab>` 的人多半是想要 `work`。`tools/test_matcher.zsh` 盯的
就是这条。

**`compadd -U` 会吃掉你敲的字。** `-U` 关掉匹配检查的同时，也让补全系统
不知道候选和当前词的对应关系，它只能退而求其次去插「所有候选的公共
前缀」。两个中文候选的公共前缀是空串，于是 `cd wd<Tab>` 直接变成 `cd`。
解法是补完之后设 `compstate[insert]=menu`，绕开公共前缀那条路。

**先跑原生补全再补拼音。** 反过来的话菜单会从某个中文目录开始循环，而敲
`cd w<Tab>` 的人多半是想要 `work`。

**别把原生补全函数写死成 `_cd`。** 早期版本这么干过，结果 `ZPT_COMMANDS`
看着能随便加命令、实际一加就把那个命令的补全废掉——`_cd` 只补目录，
`ls rep<Tab>` 补不出 `report.txt`，而且静默无报错。现在原函数是注册时从
`$_comps` 里存下来的。

**`$#assoc` 是 O(n)。** `_zpt_load_dict` 一开始写成 `(( $#_zpt_dict )) && return`，
而它每个汉字被调一次——两万条的词表上一次 `$#` 要 0.4ms，光这一句就占掉
建索引 90% 的时间。改成标志位之后建 500 个索引从 960ms 降到 40ms。

**`assoc['键']=值` 不会剥掉引号。** 磁盘缓存一开始就是这么写的，文件看着
有内容，读回来一条都对不上，每个 shell 都在默默重建全部索引。必须写成
`assoc+=( 键 值 )`。

**别开 `err_return`。** 这份代码里到处是 `(( ... ))` 当布尔用，而算术
表达式求值为 0 时退出码是 1，`err_return` 会把函数从中间掐断。入口函数
的 `emulate -L zsh` 已经把选项拉回默认，作用范围包含嵌套调用。

**`zpty -w` 会自作主张补一个换行。** 端到端测试里敲完 `ls rep<Tab>` 命令
就直接执行了，后面所有用例整体错位。要按键不换行得写 `zpty -wn`。顺带
一提，敲键和回车得分开等：敲键（含 Tab）不产生新提示符，去等提示符只会
白等满超时。

**别去解析 pty 的屏幕输出。** 里面混着按键回显和 zle 重绘，看起来像
`cd wd文档/` 这种东西，其实命令行里是对的，纯属自己吓自己。要验证就让
子 shell 把 `$PWD` 或 `$BUFFER` 写进文件。

## 已知限制

- 挂到有子命令的命令（`git`、`docker`）上会在子命令位置冒出文件候选，
  所以默认表里没有它们。
- 多段路径只匹配最后一段。`cd wd/xm` 里的 `wd/` 必须是真实存在的路径，
  想要逐段展开那是 zoxide 的活。
- 不支持乱序和跳字。`wgz` 不会匹配 `我的工作`——必须连续。换来的是候选
  列表干净，Tab 一下通常就一两个结果。
- 多音字按读音表全展开，`重`（zhong/chong）、`行`（xing/hang）这类字会
  让候选变多。目前没有按词频打分排序。
- 只覆盖 CJK 基本区。扩展区的生僻字、日文假名当作「可跳过的字符」处理。
- 和 fzf-tab 一起用时候选展示由 fzf-tab 接管，没有系统测过。

## 开发

```zsh
zsh tools/doctor.zsh         # 体检：不依赖 zpty，只看插件本身能不能跑
zsh tools/run_tests.zsh      # 全部测试 + 基准
zsh tools/test_match.zsh     # 匹配层单元测试（32 条）
zsh tools/test_complete.zsh  # cd 的端到端，用 zpty 起真实交互式 zsh（14 条）
zsh tools/test_matcher.zsh   # matcher-list 回归（4 条）
zsh tools/test_commands.zsh  # 挂到 ls / 无原生补全的命令上（6 条）
zsh tools/bench.zsh 500      # 延迟基准

pip install pypinyin && python3 tools/gen_dict.py   # 重新生成词表
```

端到端那几组要起一个 pty 里的交互式 zsh，对环境比较敏感。它们不会卡死：
每一步等提示符最多 `ZPT_TEST_TIMEOUT` 秒（默认 5），超时会把子 shell 到
那一刻的原始输出打出来，通常一眼能看出是启动报错还是提示符没匹配上。
子 shell 用 `zsh -d` 启动，跳过 `/etc/zshrc` 这类全局配置——macOS 的
`/etc/zshrc` 会按 `TERM_PROGRAM` 再 source 一层终端集成脚本、挂 precmd
钩子、改提示符，测试不该受它影响。

要是这几组在你机器上还是不对劲，先跑 `zsh tools/doctor.zsh`：它不用 pty，
能把「插件坏了」和「测试环境不对」分开。

## License

MIT
