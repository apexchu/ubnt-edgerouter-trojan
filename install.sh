#!/bin/bash

#parameters initialisations
read -p "请输入服务器地址: " SERVER_IP
echo $SERVER_IP
read -p "请输入SSL验证域名：" SERVER_DOMAINAME
echo $SERVER_DOMAINAME
read -p "请输入服务器端口: " SERVER_PORT
echo $SERVER_PORT
read -p "请输入密码: " SERVER_PASS
echo $SERVER_PASS

echo "信息如下，请核对："
green="\033[0;32m"
end="\033[0m"
echo -e "${green}服务器地址：$SERVER_IP"
echo "端口："$SERVER_PORT
echo "SSL域名："$SERVER_DOMAINAME
echo -e "密码："$SERVER_PASS${end}
echo "是否继续？"
select yn in "Yes" "No"; do
    case $yn in
        Yes ) echo "OK!";break;;
        No ) exit;;
    esac
done


DEFPATH=/usr/bin
CONFIGPATH=/config/scripts

#copy pdnsd and trojan to /usr/bin
test -d $DEFPATH || exit 0
cp -f bin/mips64/* $DEFPATH
[ -z "$RUNAS" ] && RUNAS=nobody
#chown +x for pdnsd and trojan
chown $RUNAS $DEFPATH/pdnsd
chown $RUNAS $DEFPATH/pdnsd-ctl
chown $RUNAS $DEFPATH/trojan
#chown +x for pdnsd and trojan
chmod +x $DEFPATH/pdnsd
chmod +x $DEFPATH/pdnsd-ctl
chmod +x $DEFPATH/trojan

#create /lib32 directory and copy library fils to /lib32
test -d /lib32 || mkdir /lib32
cp -f lib32/* /lib32
chown -R $RUNAS /lib32

#trojan
test -d $CONFIGPATH/trojan || mkdir $CONFIGPATH/trojan
sed -i "s|{ip}|$SERVER_IP|g" conf.d/trojan-tcp-udp.json
sed -i "s|{domainame}|$SERVER_DOMAINAME|g" conf.d/trojan-tcp-udp.json
sed -i "s|{port}|$SERVER_PORT|g" conf.d/trojan-tcp-udp.json
sed -i "s|{pass}|$SERVER_PASS|g" conf.d/trojan-tcp-udp.json
cp -f conf.d/trojan-tcp-udp.json $CONFIGPATH/trojan


#pdnsd
PDNSCACHE=/var/cache/pdnsd
test -d  $PDNSCACHE || mkdir $PDNSCACHE
sed -i "s|{cache}|$PDNSCACHE|g" conf.d/pdnsd.conf
cp -f conf.d/pdnsd.conf $CONFIGPATH/trojan

#dnsmasq
WORKDIR="$(mktemp -d)"
SERVERS=(223.5.5.5)
#create config directory and copy config files from conf.d
echo "Downloading latest configurations..."
git clone --depth=1 https://github.com/felixonmars/dnsmasq-china-list.git "$WORKDIR"
#git clone --depth=1 https://pagure.io/dnsmasq-china-list.git "$WORKDIR"
#git clone --depth=1 https://github.com/felixonmars/dnsmasq-china-list.git "$WORKDIR"
#git clone --depth=1 https://bitbucket.org/felixonmars/dnsmasq-china-list.git "$WORKDIR"
#git clone --depth=1 https://gitee.com/felixonmars/dnsmasq-china-list.git "$WORKDIR"
#git clone --depth=1 https://gitlab.com/felixonmars/dnsmasq-china-list.git "$WORKDIR"
#git clone --depth=1 https://code.aliyun.com/felixonmars/dnsmasq-china-list.git "$WORKDIR"
#git clone --depth=1 http://repo.or.cz/dnsmasq-china-list.git "$WORKDIR"

CONF_WITH_SERVERS=(accelerated-domains.china)
CONF_SIMPLE=(bogus-nxdomain.china)
echo "Removing old configurations..."
for _conf in "${CONF_WITH_SERVERS[@]}" "${CONF_SIMPLE[@]}"; do
rm -f /etc/dnsmasq.d/"$_conf"*.conf
done

echo "Installing new configurations..."
for _conf in "${CONF_SIMPLE[@]}"; do
cp "$WORKDIR/$_conf.conf" "/etc/dnsmasq.d/$_conf.conf"
done

for _server in "${SERVERS[@]}"; do
for _conf in "${CONF_WITH_SERVERS[@]}"; do
cp "$WORKDIR/$_conf.conf" "/etc/dnsmasq.d/$_conf.$_server.conf"
done

sed -i "s|^\(server.*\)/[^/]*$|\1/$_server|" /etc/dnsmasq.d/*."$_server".conf
done

touch /etc/dnsmasq.d/final.conf
echo 'server=/#/127.0.0.1#5335' > /etc/dnsmasq.d/final.conf
echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf

echo "Restarting dnsmasq service..."
service dnsmasq restart

echo "Cleaning up..."
rm -r "$WORKDIR"

#tptables
#curl 'https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt' > cn_ipv4.list
echo "Downloading latest china ips"
curl 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' | grep ipv4 | grep CN | awk -F\| '{ printf("%s/%d\n", $4, 32-log($5)/log(2)) }' > cn_ipv4.list
wait
CHAIN_NAME='BYPASSLIST'

set -e

#del chnroute
ipset destroy chnlist
iptables -t nat -F $CHAIN_NAME
iptables -t nat -X $CHAIN_NAME
echo 'Del_rules Done.'

# Add new ipset
#ipset destroy chnlist
ipset -N chnlist hash:net maxelem 65536

echo 'ipset processing...'
ipset add chnlist $SERVER_IP
ipset add chnlist 0.0.0.0/8
ipset add chnlist 10.0.0.0/8
ipset add chnlist 127.0.0.0/8
ipset add chnlist 169.254.0.0/16
ipset add chnlist 172.16.0.0/12
ipset add chnlist 192.168.0.0/16
ipset add chnlist 224.0.0.0/4
ipset add chnlist 240.0.0.0/4

for ip in $(cat cn_ipv4.list)
do
    ipset add chnlist $ip
done
echo 'ipset done.'

# 1. TCP
# TCP new chain $CHAIN_NAME
iptables -t nat -N $CHAIN_NAME
# TCP ipset match
iptables -t nat -A $CHAIN_NAME -p tcp -m set --match-set chnlist dst -j RETURN
# TCP redirect
iptables -t nat -A $CHAIN_NAME -p tcp -j REDIRECT --to-ports 1234
# TCP rule to prerouting chain
iptables -t nat -A PREROUTING -p tcp -j $CHAIN_NAME
# For local
#iptables -t nat -I OUTPUT -p tcp -j $CHAIN_NAME
echo 'iptables setting is done.'

#supervisord
sed -i "s|{DEFPATH}|$DEFPATH|g" conf.d/trojan-supervisord.conf
sed -i "s|{configDEFPATH}|$CONFIGPATH|g" conf.d/trojan-supervisord.conf
cp conf.d/trojan-supervisord.conf /etc/supervisor/conf.d/shadowsocks.conf
supervisorctl shutdown ; supervisord

#auto update chnipsets
sed -i "s|# SERVER_IP|SERVER_IP=$SERVER_IP|g" iptables.sh
cp -f iptables.sh $CONFIGPATH/trojan
chown $RUNAS $CONFIGPATH/trojan/iptables.sh
chmod +x $CONFIGPATH/trojan/iptables.sh
sed '$a* 3 * * * $CONFIGPATH/trojan/iptables.sh add_rules' /etc/crontab

echo "All Done"
