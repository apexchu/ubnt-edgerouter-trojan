# ubnt-edgerouter-trojan
couterm trojan for ubnt edge router 6P (mips64)

# 安装步骤以及要求 (以ER-6P为例)
1. 先设置 apt-get 的 source，然后安装supervisor
configure
set system package repository wheezy components 'main contrib non-free' 
set system package repository wheezy distribution wheezy 
set system package repository wheezy url http://archive.debian.org/debian
commit ; save
sudo -i
apt-get update
apt-get install git wget supervisor

2. 下载仓库文件并执行脚本

执行：cd ubnt-edgerouter-trojan && sudo bash ./install.sh

3. 按照提示填入服务器信息，等待脚本执行完毕后, 确认 iptables 写入成功

```
iptables -t nat -L
```

* iptables 样例  

```shell
Chain BYPASSLIST (1 references)
target     prot opt source               destination
RETURN     all  --  anywhere             123.123.123.123
RETURN     all  --  anywhere             0.0.0.0/8
RETURN     all  --  anywhere             10.0.0.0/8
RETURN     all  --  anywhere             127.0.0.0/8
RETURN     all  --  anywhere             link-local/16
RETURN     all  --  anywhere             172.16.0.0/12
RETURN     all  --  anywhere             192.168.0.0/16
RETURN     all  --  anywhere             base-address.mcast.net/4
RETURN     all  --  anywhere             240.0.0.0/4
RETURN     tcp  --  anywhere             anywhere             match-set chnlist dst
```

4. 架构是mips64(适用ER-6P,ER-12P),其他架构需要自己编译。解压缩后移动到 /usr/bin/ 中或者 /usr/local/bin/ 确保 ss-redir ss-tunnel 可以直接执行。不知道自己是什么架构的输入 uname -a 查看

# supervisord 操作帮助
```
关闭supervisord： supervisorctl shutdown 
启动supervisord：supervisord
```
