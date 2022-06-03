#!/bin/bash

set -e

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


PATH=/usr/bin
CONFPATH=/config/scripts

#copy pdnsd and trojan to /usr/bin
test -d $PATH || exit 0
sudo cp -f y bin/mips64/* $PATH
[ -z "$RUNAS" ] && RUNAS=nobody
#chown +x for pdnsd and trojan
sudo chown $RUNAS $PATH/pdnsd
sudo chown $RUNAS $PATH/pdnsd-ctl
sudo chown $RUNAS $PATH/trojan
#chown +x for pdnsd and trojan
sudo chmod +x $PATH/pdnsd
sudo chmod +x $PATH/pdnsd-ctl
sudo chmod +x $PATH/trojan

#create /lib32 directory and copy library fils to /lib32
test -d /lib32 || mkdir /lib32
sudo cp -f y lib32/* /lib32
sudo chown -r $RUNAS /lib32

#trojan
test -d $CONFPATH/trojan || mkdir $CONFPATH/trojan
sudo sed -i "s|{ip}|$SERVER_IP|g" conf.d/trojan-tcp-udp.json
sudo sed -i "s|{domainame}|$SERVER_DOMAINAME|g" conf.d/trojan-tcp-udp.json
sudo sed -i "s|{port}|$SERVER_PORT|g" conf.d/trojan-tcp-udp.json
sudo sed -i "s|{pass}|$SERVER_PASS|g" conf.d/trojan-tcp-udp.json
cp -f y conf.d/trojan-tcp-udp.json $CONFPATH/trojan


#pdnsd
PDNSCACHE=/var/cache/pdnsd
test -d  $PDNSCACHE || mkdir $PDNSCACHE
sudo sed -i "s|{cache}|$PDNSCACHE|g" conf.d/pdnsd.conf
cp -f y conf.d/pdnsd.conf $CONFPATH/trojan

#dnsmasq
WORKDIR="$(mktemp -d)"
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
sudo rm -f /etc/dnsmasq.d/"$_conf"*.conf
done

echo "Installing new configurations..."
for _conf in "${CONF_SIMPLE[@]}"; do
sudo cp "$WORKDIR/$_conf.conf" "/etc/dnsmasq.d/$_conf.conf"
done

for _server in "${SERVERS[@]}"; do
for _conf in "${CONF_WITH_SERVERS[@]}"; do
sudo cp "$WORKDIR/$_conf.conf" "/etc/dnsmasq.d/$_conf.$_server.conf"
done

sudo sed -i "s|^\(server.*\)/[^/]*$|\1/$_server|" /etc/dnsmasq.d/*."$_server".conf
done

sudo touch /etc/dnsmasq.d/final.conf
echo 'server=/#/127.0.0.1#5335' > /etc/dnsmasq.d/final.conf
echo 'conf-dir=/etc/dnsmasq.d/,*.conf' >> /etc/dnsmasq.conf

echo "Restarting dnsmasq service..."
sudo service dnsmasq restart

echo "Cleaning up..."
sudo rm -r "$WORKDIR"

#tptables
#curl 'https://raw.githubusercontent.com/17mon/china_ip_list/master/china_ip_list.txt' > cn_ipv4.list
echo "Downloading latest china ips"
curl 'http://ftp.apnic.net/apnic/stats/apnic/delegated-apnic-latest' | grep ipv4 | grep CN | awk -F\| '{ printf("%s/%d\n", $4, 32-log($5)/log(2)) }' > cn_ipv4.list
wait
CHAIN_NAME='BYPASSLIST'

#del chnroute
sudo ipset destroy chnroute
sudo iptables -t nat -F $CHAIN_NAME
sudo iptables -t nat -X $CHAIN_NAME
echo 'Del_rules Done.'

# Add new ipset
ipset destroy chnlist
ipset -N chnlist hash:net maxelem 65536

echo 'ipset processing...'
sudo ipset add chnlist $SERVER_IP
sudo ipset add chnlist 0.0.0.0/8
sudo ipset add chnlist 10.0.0.0/8
sudo ipset add chnlist 127.0.0.0/8
sudo ipset add chnlist 169.254.0.0/16
sudo ipset add chnlist 172.16.0.0/12
sudo ipset add chnlist 192.168.0.0/16
sudo ipset add chnlist 224.0.0.0/4
sudo ipset add chnlist 240.0.0.0/4

for ip in $(sudo cat cn_ipv4.list)
do
    sudo ipset add chnlist $ip
done
echo 'ipset done.'

# 1. TCP
# TCP new chain $CHAIN_NAME
sudo iptables -t nat -N $CHAIN_NAME
# TCP ipset match
sudo iptables -t nat -A $CHAIN_NAME -p tcp -m set --match-set chnlist dst -j RETURN
# TCP redirect
sudo iptables -t nat -A $CHAIN_NAME -p tcp -j REDIRECT --to-ports 1234
# TCP rule to prerouting chain
sudo iptables -t nat -A PREROUTING -p tcp -j $CHAIN_NAME
# For local
#iptables -t nat -I OUTPUT -p tcp -j $CHAIN_NAME
echo 'iptables setting is done.'

#supervisord
sudo sed -i "s|{path}|$PATH|g" conf.d/trojan-supervisord.conf
sudo sed -i "s|{configpath}|$CONFPATH|g" conf.d/trojan-supervisord.conf
sudo cp conf.d/trojan-supervisord.conf /etc/supervisor/conf.d/shadowsocks.conf
sudo supervisorctl shutdown ; sudo supervisord

#auto update chnipsets
sudo sed -i "s|# SERVER_IP|SERVER_IP=$SERVER_IP|g" iptables.sh
sudo cp -f y iptables.sh $CONFPATH/trojan
sudo chown $RUNAS $CONFPATH/trojan/iptables.sh
sudo chmod +x $CONFPATH/trojan/iptables.sh
sudo sed '$a* 3 * * * $CONFPATH/trojan/iptables.sh add_rules' /etc/crontab

echo "All Done"
