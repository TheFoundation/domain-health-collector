#!/bin/bash

#todo : git reset head ,  git directory 
test -f ~/.domainhealth.conf || (echo "NO CONFIG";exit 3 )
. ~/.domainhealth.conf

_ssl_host_enddate_days() {     end="$(date +%Y-%m-%d --date="$( echo | openssl s_client -connect "$1" 2>/dev/null |openssl x509 -enddate -noout |cut -d= -f 2)" )"; date_diff=$(( ($(date -d "$end UTC" +%s) - $(date -d "$(date +%Y-%m-%d) UTC" +%s) )/(60*60*24) ));printf '%s: %s' "$date_diff" "$1" ; } ;

_vhost_extract_docker() { 
##gen list
 containers=$(docker ps --format '{{.Names}}' |grep -v -e nginx -e portainer|grep "\." ) ; 
 #docker exec $i printenv SSH_PORT
 webcontainers=$(for i in $containers;do imagetype=$(docker inspect --format '{{.Config.Image}}' $i) ; echo $imagetype |grep -q -e ^mariadb -e _cron$ -e memcached -e _database -e piwik-cron -e nginx-gen -e nginx-letsencrypt -e nginx-proxy && (echo will not proc $i"     "  >&2)|| ( echo -en "$i ";) ; done)
 (for i in $webcontainers;do imagetype=$(docker inspect --format '{{.Config.Image}}' $i)  ;echo $imagetype | grep -q nginx-redirect && ( echo "R@"$i"@"$(docker exec $i printenv VIRTUAL_HOST)"@@"$(docker exec $i printenv SERVER_REDIRECT_SCHEME)"://"$(docker exec $i printenv SERVER_REDIRECT)$(docker exec $i printenv SERVER_REDIRECT_PATH)) ||  ( echo "H@"$i"@"$(docker exec $i printenv VIRTUAL_HOST)"@"$(docker port $i|grep ^22|wc -l|grep -q ^0$ ||docker inspect --format '22/tcp:{{ (index (index .NetworkSettings.Ports "22/tcp") 0).HostPort }}' $i | grep "22/tcp" |cut -d":" -f2)"@") ; done > /tmp/vhostconf.domainlist)
 
#cat /tmp/vhostconf.domainlist
echo ; } ;

_vhost_extract_apache() {
	containers=$(docker ps --format '{{.Names}}' |grep -v -e nginx -e portainer );
	apachecfg="$(apache2ctl -S 2>/dev/null || apachectl -S 2>/dev/null)";

	configlines=$(echo "$apachecfg"|grep -e namevhost -e "alias "|sed 's/.\+namevhost /@@/g;s/.\+ alias /:/g'|tr -d '\n'|sed 's/$/@@/g'|sed 's/@@/\n/g');
	echo "$configlines"|grep -v ^$|while read cur_config; do 
						host=$(echo $cur_config|cut -d" " -f1);
						conffile=$(echo $cur_config|cut -d"(" -f2 |cut -d":" -f1);
						vhosts=$(echo $cur_config | cut -d")" -f2-|grep -v ^$|cut -d":" -f2-|sed 's/:/,/g' )
						vhostfield=$(echo $host","$vhosts|sed 's/,$//g')
						redir=$((curl -sw "\n\n%{redirect_url}" "https://${host}" | tail -n 1|grep -q http ) && echo "R" || echo "H" )
						ssh_port=$(echo "$containers"|grep -q "^"$host"$" && echo -n $(docker port $host|grep ^22|wc -l|grep -q ^0$ ||docker inspect --format '22/tcp:{{ (index (index .NetworkSettings.Ports "22/tcp") 0).HostPort }}' $host | grep "22/tcp" |cut -d":" -f2))
						echo $redir"@"$host"@"$vhostfield"@"$ssh_port
	done |  awk '!x[$0]++' > /tmp/vhostconf.domainlist
}
	
_vhost_extract_nginx() {
	which docker 2>/dev/null && containers=$(docker ps --format '{{.Names}}' |grep -v -e nginx -e portainer );
	cat /etc/nginx/sites-enabled/*|sed 's/^\( \|\t\)\+#.\#//g;s/#.\+//g'|grep -v ^$|sed 's/server /@@server /g;s/^/→→/g'|tr -d '\n'|sed 's/@@/\n/g'|grep "listen 443" |sed 's/→→/\n/g'|grep -e "server " -e server_name |sed 's/\;.\+//g'|sed 's/server /@@server /g'|tr -d '\n'|sed 's/@@/\n/g'|grep -v ^$|sed 's/^server {//g;s/^\( \|\t\)\+//g;s/server_name//;s/;//g'|while read vhosts ;do 
	vhostfield=$(echo $vhosts|sed 's/ \+/ /g;s/ /,/g');
	host=$(echo "$vhosts"|sed 's/ /\n/g'|grep -v "*"|head -n1);
	redir=$((curl -sw "\n\n%{redirect_url}" "https://${host}" | tail -n 1|grep -q http ) && echo "R" || echo "H" )
	which docker 2>/dev/null && ssh_port=$(echo "$containers"|grep -q "^"$host"$" && echo -n $(docker port $host|grep ^22|wc -l|grep -q ^0$ ||docker inspect --format '22/tcp:{{ (index (index .NetworkSettings.Ports "22/tcp") 0).HostPort }}' $host | grep "22/tcp" |cut -d":" -f2))
	echo $redir"@"$host"@"$vhostfield"@"$ssh_port
done  |  awk '!x[$0]++' > /tmp/vhostconf.domainlist
echo ; } ;

_websrv_health_client() { 
 	[ -z "$CLIENT_GIT_REPO" ] && ( echo "no target repo" ; exit 3 )

#
test -d /tmp/.domain-health-list/.git && ( cd /tmp/.domain-health-list/ ; git pull --recurse-submodules ) || (rm -rf /tmp/.domain-health-list/; git clone $CLIENT_GIT_REPO /tmp/.domain-health-list ; cd /tmp/.domain-health-list; git pull --recurse-submodules )
test -d /tmp/.domain-health-lists/ || ( rm -rf /tmp/.domain-health-lists ; mkdir /tmp/.domain-health-lists )

cd /tmp/.domain-health-lists &&  ( cat /tmp/.domain-health-list/repolist  | while read repository ;do git clone "$repository" ;done) 

cd /tmp/;

### if force-push happened , pull from beginning
 for fold in /tmp/.domain-health-lists/domainlist-*;do cd $fold;git update-ref -d HEAD;git rm -fr .;git pull ;done

# for fold in /tmp/.domain-health-lists/domainlist-*;do cd $fold;git reset --hard origin/master;git pull ;done
# for fold in /tmp/.domain-health-lists/domainlist-*;do cd $fold;git pull ;done
# cd /tmp/.domain-health-lists/ ; git pull --recurse-submodules

 #!! 500 ( internal server err) → contao no startpoint , cache failures, php code errors etc.
 #!! 503 onlyoffice cant write
 #!! 503 Service Temporarily Unavailable
#test status 
statusgetter() {
find /tmp/.domain-health-lists/ -name domainlist|while read listfile;do cat "$listfile";done  |grep -v -e "^H@@@$" -e "^R@@@$"|awk '!x[$0]++' |while read a ;do ( target="";type=${a/%@*/};
if [ "$type" == "H" ];then  url=$(echo $a|cut -d" " -f1|cut -d@ -f3|cut -d"," -f1); http_stat=$(curl -sw '%{http_code}' https://$url -o /dev/null 2>&1);fi
if [ "$type" == "R" ];then  url=$(echo $a|cut -d" " -f1|cut -d@ -f3|cut -d"," -f1);http_stat=$(curl -sw '%{http_code}' https://$url -o /dev/null 2>&1); target=$(curl -I -L -s -S -w %{url_effective} -o /dev/null $url) ; fi; echo $http_stat"@"$a"@"$target ) & done 
}
statusobject="$(statusgetter)"
statuslength=$(echo "$statusobject"|wc -l)

(
##w2ui json init
count=1;
echo '{';echo '"total": '${statuslength}",";echo '"records": [';
#entry gen
echo "$statusobject" |while read entry;do 
	
	ssldays=$(_ssl_host_enddate_days $(echo $entry|cut -d"@" -f 3)":443" |cut -d":" -f1);
	echo "$entry"|awk -F @ '{print "{ \"recid\": \""$count"\", \"type\": \""$2"\", \"status\": \""$1"\", \"vhost\": \""$3"\", \"ssh\": \""$5"\", \"ssldays\": \""'${ssldays}'"\", \"redirect\": \""$6"\", \"alias\": \""$4"\" }"}'|tr -d '\n';
	[ $count  -ne $statuslength ] && echo "," ## no comma on last line
	let count++;
	done
echo -e "\t"']';echo '}';
) >  /tmp/.domainhealth-www/domainlist.json

wait
 echo -n ; } ;

_host_extract() {
	[ -z "$HOST_GIT_REPO" ] && ( echo "no target repo" ; exit 3 )
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
#		test -d /tmp/domainlist-$(hostname -f) && ( 
#		test -d /tmp/domainlist-$(hostname -f)/.git && rm -rf /tmp/domainlist-$(hostname -f)/.git 
#		cd /tmp/domainlist-$(hostname -f); 
#		git init
#		git remote add origin $HOST_GIT_REPO

		test -d /tmp/domainlist-$(hostname -f)/.git && rm -rf /tmp/domainlist-$(hostname -f)/
		git clone $HOST_GIT_REPO /tmp/domainlist-$(hostname -f)/ && cat /tmp/vhostconf.domainlist > /tmp/domainlist-$(hostname -f)/domainlist
		cd /tmp/domainlist-$(hostname -f) &&	git add domainlist && 	git commit -am $(hostname -f)"domain list "$(date -u +%Y-%m-%d-%H.%M) && git config user.name domainlist@$(hostname -f) && git push -f origin master
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
