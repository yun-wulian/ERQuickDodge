实现艾尔登法环的无延迟闪避。

主要功能：
1，闪避无延迟
2，长按闪避，在一定时间后接续为疾跑动作
3，闪避、跳跃、防御可以取消任意动作
4，其它功能。
以上所有功能可配置开关，长按闪避到疾跑时间可配置长短。

需要在其它大修MOD的action/script/c0000.hks的最底下，在global = {}前添加一行：pcall(loadfile("quickDodge\\quickDodge.lua"))
