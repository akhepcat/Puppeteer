#!/bin/bash
PROG="${0##*/}"
DATE="$(date +%Y%m%d-%H%M)"
HOSTS=puppeteer.hosts
CMDS=puppeteer.commands
###

CONNECT_ONLY=0
ALL=0
VALIDATE=1
host=""
###

usage() {
        echo "${PROG} [-an] [-ch] host"
        echo "choose one of"
        echo "	-a		All hosts"
        echo "	-h [host]	specific host"
        echo "	-c		connect test"
        echo "	-n		no verification of host configuration with ${HOSTS}"
        echo ""
}

do_host() {
	host=${1}

	if [ 1 -eq ${VALIDATE} ]
	then
		thost=$(grep "$host" ${HOSTS} | grep -v '^#')
		[[ -n "${thost}" ]] && host=${thost}
	fi

	[[ -z "${host##*@*}" ]] && user=${host%%@*}
	host=${host##*@}
	[[ -z "${host##*:*}" ]] && distro=${host##*:}
	host=${host%%:*}

	echo "host: ${host}, user: ${user:-root}, distro: ${distro:-generic}, commands: ${CMDS}${distro:+.$distro}"


	if [ 1 -eq ${CONNECT_ONLY} ]
	then
		ssh -4 -v -o ConnectTimeout=5 -i ${HOME}/.ssh/id_rsa.puppeteer -i ${HOME}/.ssh/id_ecdsa.puppeteer ${user:-root}@${host}
	else
		echo "MARK --${DATE}-- host: ${host}, user: ${user:-root}, distro: ${distro:-generic}, commands: ${CMDS}${distro:+.$distro}" >> ${host}.log
		ssh -4 -o ConnectTimeout=5 -i ${HOME}/.ssh/id_rsa.puppeteer -i ${HOME}/.ssh/id_ecdsa.puppeteer ${user:-root}@${host} < ${CMDS}${distro:+.$distro} 2>&1 | tee -a ${host}.log
	fi

	echo "complete"
	echo ""

	unset user
	unset distro
}

all_hosts() {

	for host in $(grep -v ^# ${HOSTS});
	do
		do_host ${host}
	done
}

if [ ! -r ${HOME}/.ssh/id_rsa.puppeteer -a ! -r ${HOME}/.ssh/id_ecdsa.puppeteer ]
then
	echo "please create the shared certificates:"
	echo "   ${HOME}/.ssh/id_rsa.puppeteer"
	echo "   ${HOME}/.ssh/id_ecdsa.puppeteer"
	echo ""
	exit 1
fi

if [ -z "$*" ]
then
	usage
	exit 1
fi


while getopts "anch:" param; do
 case $param in
  a) ALL=1 ;;
  c) CONNECT_ONLY=1;;
  h) HOST_ONLY=1; host=${OPTARG} ;;
  n) VALIDATE=0 ;;
  *) usage; exit 1;;
 esac
done

if [ -z "${host}" ]
then
	if [ 1 -eq ${ALL} ]
	then
		[[ ${CONNECT_ONLY} -eq 1 ]] && echo "connect test only:"
		echo "processing all hosts in ${HOSTS}"
		all_hosts
		exit 0
	else
		echo "Specify a [-h host] or  [-a]ll hosts"
		exit 1
	fi
else
	do_host ${host}
fi
