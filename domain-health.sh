#!/bin/bash

#todo : git reset head ,  git directory 
test -f ~/.domainhealth.conf || (echo "NO CONFIG";exit 3 )
. ~/.domainhealth.conf


_vhost_extract_docker() { 
##gen list
 containers=$(docker ps --format '{{.Names}}' |grep -v -e nginx -e portainer|grep "\." ) ; 
 webcontainers=$(for i in $containers;do imagetype=$(docker inspect --format '{{.Config.Image}}' $i) ; echo $imagetype |grep -q -e ^mariadb -e _cron$ -e memcached -e _database -e piwik-cron -e nginx-gen -e nginx-letsencrypt -e nginx-proxy && (echo will not proc $i"     "  >&2)|| ( echo -en "$i ";) ; done)
 (for i in $webcontainers;do imagetype=$(docker inspect --format '{{.Config.Image}}' $i)  ;echo $imagetype | grep -q nginx-redirect && ( echo "R@"$i"@"$(docker exec $i printenv VIRTUAL_HOST)"@"$(docker exec $i printenv SERVER_REDIRECT_SCHEME)"://"$(docker exec $i printenv SERVER_REDIRECT)$(docker exec $i printenv SERVER_REDIRECT_PATH)) ||  ( echo "H@"$i"@"$(docker exec $i printenv VIRTUAL_HOST)"@"$(docker exec $i printenv SSH_PORT)) ; done > /tmp/vhostconf.domainlist)
 
#cat /tmp/vhostconf.domainlist
echo ; } ;

_vhost_extract_apache() {
	containers=$(docker ps --format '{{.Names}}' |grep -v -e nginx -e portainer );
	apachecfg="$(apache2ctl -S 2>/dev/null || apachectl -S 2>/dev/null)";

	configlines=$(echo "$apachecfg"|grep -e namevhost -e "alias "|sed 's/.\+namevhost /@@/g;s/.\+ alias /:/g'|tr -d '\n'|sed 's/$/@@/g'|sed 's/@@/\n/g');
	echo "$configlines"|while read cur_config; do 
						host=$(echo $cur_config|cut -d" " -f1);
						conffile=$(echo $cur_config|cut -d"(" -f2 |cut -d":" -f1);
						vhosts=$(echo $cur_config | cut -d")" -f2-|grep -v ^$|cut -d":" -f2-|sed 's/:/,/g' )
						vhostfield=$(echo $host","$vhosts|sed 's/,$//g')
						redir=$((curl -sw "\n\n%{redirect_url}" "https://${host}" | tail -n 1|grep -q http ) && echo "R" || echo "H" )
						ssh_port=$(echo "$containers"|grep -q "^"$host"$" && echo -n $(docker exec $host printenv SSH_PORT))
						echo $redir"@"$host"@"$vhostfield"@"$ssh_port
	done > /tmp/vhostconf.domainlist


	}
	
_vhost_extract_nginx() {
	containers=$(docker ps --format '{{.Names}}' |grep -v -e nginx -e portainer );
 cat /etc/nginx/sites-enabled/*|sed 's/^\( \|\t\)\+#.\#//g;s/#.\+//g'|grep -v ^$|sed 's/server /@@server /g;s/^/→→/g'|tr -d '\n'|sed 's/@@/\n/g'|grep "listen 443" |sed 's/→→/\n/g'|grep -e "server " -e server_name |sed 's/\;.\+//g'|sed 's/server /@@server /g'|tr -d '\n'|sed 's/@@/\n/g'|grep -v ^$|sed 's/^server {//g;s/^\( \|\t\)\+//g;s/server_name//;s/;//g'|while read vhosts ;do 
	vhostfield=$(echo $vhosts|sed 's/ \+/ /g;s/ /,/g');
	host=$(echo "$vhosts"|sed 's/ /\n/g'|grep -v "*"|head -n1);
	redir=$((curl -sw "\n\n%{redirect_url}" "https://${host}" | tail -n 1|grep -q http ) && echo "R" || echo "H" )
	ssh_port=$(echo "$containers"|grep -q "^"$host"$" && echo -n $(docker exec $host printenv SSH_PORT))
	echo $redir"@"$host"@"$vhostfield"@"$ssh_port
done > /tmp/vhostconf.domainlist
echo ; } ;


_websrv_health_client() { 
 	[ -z "$CLIENT_GIT_REPO" ] && ( echo "no target repo" ; exit 3 )

test -d /tmp/.domain-health-lists/.git && ( cd /tmp/.domain-health-lists/ ; git pull --recurse-submodules ) || (rm -rf /tmp/.domain-health-lists/.git; git clone $CLIENT_GIT_REPO /tmp/.domain-health-lists ; git submodule update --init --recursive )
for fold in /tmp/.domain-health-lists/*;do cd $fold;git reset --hard origin/master;done


 #!! 500 ( internal server err) → contao no startpoint
 #!! 503 onlyoffice cant write
 #!! 503 Service Temporarily Unavailable
#test status 
find /tmp/.domain-health-lists/ -name domainlist|while read listfile;do cat "$listfile";done  |while read a ;do ( target="";type=${a/%@*/};
if [ "$type" == "H" ];then  url=$(echo $a|cut -d" " -f1|cut -d@ -f3|cut -d"," -f1); http_stat=$(curl -sw '%{http_code}' https://$url -o /dev/null 2>&1);fi
if [ "$type" == "R" ];then  url=$(echo $a|cut -d" " -f1|cut -d@ -f3|cut -d"," -f1);http_stat=$(curl -sw '%{http_code}' $url -o /dev/null 2>&1); target=$(curl -Ls -w %{url_effective} -o /dev/null $url) ; fi; echo $http_stat"@"$a"@"$target ) & done

wait
 echo -n ; } ;

_host_extract() {
	[ -z "$HOST_GIT_REPO" ] && ( echo "no target repo" ; exit 3 )

		#websrvid=$(ls -l /proc/$(fuser 443/tcp 2>/dev/null|cut -f2|sed 's/ //g')/exe)
		websrvid=$(ls -l /proc/$(fuser 443/tcp 2>/dev/null|awk '{print $1}')/exe)
		case "$websrvid" in
		   *docker-proxy ) 
		             #echo docker;
		             _vhost_extract_docker ;;
		   *apache2 ) 
		             #echo apache2;
		              _vhost_extract_apache ;;
		   *nginx ) 
		             #echo nginx;
		              _vhost_extract_nginx ;;
		
		esac
		test -d /tmp/domainlist-$(hostname -f) || mkdir /tmp/domainlist-$(hostname -f)
		
		test -d /tmp/domainlist-$(hostname -f) && ( 
		cat /tmp/vhostconf.domainlist > /tmp/domainlist-$(hostname -f)/domainlist
		test -d /tmp/domainlist-$(hostname -f)/.git && rm -rf /tmp/domainlist-$(hostname -f)/.git 
		cd /tmp/domainlist-$(hostname -f); 
		git init
		git remote add origin $HOST_GIT_REPO
		git add domainlist
		git commit -am $(hostname -f)"domain list "$(date -u +%Y-%m-%d-%H.%M)
		git config user.name domainlist@$(hostname -f)
		git push -f origin master
		)
		echo -n ; } ;


case "$1" in 
	host )
			#echo "server side";
			_host_extract ;;
	client )
			#echo "client side";
			_websrv_health_client ;;
esac
