#!/usr/bin/env zsh
# 把插件装到 ~/.zsh/zsh-pinyin-tab，并在 ~/.zshrc 末尾加一行 source。
# 可以重复跑，不会重复往 .zshrc 里加。
#
#   zsh install.zsh

emulate -L zsh
setopt err_exit no_unset

local SRC=${0:A:h}
local DEST=$HOME/.zsh/zsh-pinyin-tab
local OLD=$HOME/.zsh/zsh-pinyin-cd          # 改名前的安装位置
local RC=$HOME/.zshrc
local LINE='source ~/.zsh/zsh-pinyin-tab/zsh-pinyin-tab.plugin.zsh'

print "源目录: $SRC"
print "目标:   $DEST"
print

# 1. 拷贝
mkdir -p ${DEST:h}
if [[ -d $DEST ]]; then
  print "目标已存在，先备份成 $DEST.bak"
  rm -rf $DEST.bak
  mv $DEST $DEST.bak
fi
cp -R $SRC $DEST
rm -f $DEST/install.zsh

# 2. 删掉随包带的 .zwc，让插件用本机 zsh 重新编一份
#    zcompile 出来的是二进制词码，跨机器带过来不保险；重编只要 200ms，
#    而且只发生一次
rm -f $DEST/data/pinyin.zsh.zwc
print "已删除预编译词表，首次使用时会用本机 zsh 重新 zcompile"

# 3. 改 .zshrc
#    改名前那行 source 指向 zsh-pinyin-cd，留着的话会两份一起加载，
#    后加载的那份把 _zpt_orig 里存的原生补全函数覆盖掉。所以先换掉它。
if [[ -f $RC ]] && grep -q 'zsh-pinyin-cd.plugin.zsh' $RC; then
  cp $RC $RC.bak-$(date +%Y%m%d%H%M%S)
  sed -i.tmp 's|.*zsh-pinyin-cd/zsh-pinyin-cd\.plugin\.zsh|'"$LINE"'|' $RC
  rm -f $RC.tmp
  print "~/.zshrc 里指向旧名字 zsh-pinyin-cd 的那行已改成 zsh-pinyin-tab"
  print "（原文件备份为 ~/.zshrc.bak-*）"
elif [[ -f $RC ]] && grep -q 'zsh-pinyin-tab.plugin.zsh' $RC; then
  print "~/.zshrc 里已经有 source 行了，跳过"
else
  cp $RC $RC.bak-$(date +%Y%m%d%H%M%S) 2>/dev/null || true
  print -r -- "" >> $RC
  print -r -- "# 拼音补全 (cd wd<Tab> -> 文档)" >> $RC
  print -r -- $LINE >> $RC
  print "已追加到 ~/.zshrc（原文件备份为 ~/.zshrc.bak-*）"
fi

# 4. 旧安装目录留着没用，但也不替用户删——只提醒一句
if [[ -d $OLD ]]; then
  print
  print "注意：改名前的安装目录还在，确认新版没问题之后可以删掉："
  print "  rm -rf $OLD"
fi

print
print "配置项前缀也从 ZPC_ 换成了 ZPT_（ZPC_ 仍然认，但建议改过来）。"
print
print "装好了。执行 exec zsh 重开 shell，然后随便找个有中文目录的地方试："
print "  cd wd<Tab>"
print
print "想确认一下的话可以跑一遍测试："
print "  zsh $DEST/tools/run_tests.zsh"
