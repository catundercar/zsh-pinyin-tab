#!/usr/bin/env zsh
# 跑全部测试。
#   zsh tools/run_tests.zsh

emulate -L zsh
local here=${0:A:h}
local -i rc=0

print '== 匹配层单元测试 =='
zsh $here/test_match.zsh || rc=1
print
print '== 端到端补全测试（zpty 起真实交互式 zsh）=='
zsh $here/test_complete.zsh || rc=1
print
print '== matcher-list 回归（忽略大小写不能被拼音挤掉）=='
zsh $here/test_matcher.zsh || rc=1
print
print '== 挂到 cd 以外的命令上 =='
zsh $here/test_commands.zsh || rc=1
print
print '== 延迟基准 =='
zsh $here/bench.zsh 500

return $rc
