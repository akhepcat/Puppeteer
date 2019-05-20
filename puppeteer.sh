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
        echo "	-a		  All hosts"
        echo "	-h [host]	  specific host"
        echo "	-d [commands.txt] debugging/alternate commands text"
        echo "	-c		  connect test"
	echo "  -b                check for broken upgrades from last-run data"
        echo "	-n		  no verification of host configuration with ${HOSTS}"
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

	MYCMDS=${CMDS}${distro:+.$distro}
	[[ -n "${DCMDS}" ]] && MYCMDS=${DCMDS}

	echo "host: ${host}, user: ${user:-root}, distro: ${distro:-generic}, commands: ${MYCMDS}"

	SSHOPTS="-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o IdentitiesOnly=yes -o ConnectTimeout=5"
	SSHIDS="-i ${HOME}/.ssh/id_rsa.puppeteer -i ${HOME}/.ssh/id_ecdsa.puppeteer"

	if [ 1 -eq ${CONNECT_ONLY} ]
	then
		ssh -4 -v ${SSHOPTS} ${SSHIDS} ${user:-root}@${host}
	else
		echo "MARK --${DATE}-- host: ${host}, user: ${user:-root}, distro: ${distro:-generic}, commands: ${MYCMDS}" >> ${host}.log
		ssh -4 ${SSHOPTS} ${SSHIDS} ${user:-root}@${host} < ${MYCMDS} 2>&1 | tee -a ${host}.log
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
	echo "   ssh-keygen -t rsa -f ${HOME}/.ssh/id_rsa.puppeteer"
	echo "   ssh-keygen -t ecdsa -f ${HOME}/.ssh/id_ecdsa.puppeteer"
	echo ""
	echo "Next copy the text from the .pub file into each hosts' authorized_keys file"
	echo "either manually, or using the ssh-copy-id command"
	echo ""
	exit 1
fi

if [ -z "$*" ]
then
	usage
	exit 1
fi


while getopts "banch:d:" param; do
 case $param in
  a) ALL=1 ;;
  b) BROKEN_ONLY=1;;
  c) CONNECT_ONLY=1;;
  h) HOST_ONLY=1; host=${OPTARG} ;;
  d) DCMDS=${OPTARG} ;;
  n) VALIDATE=0 ;;
  *) usage; exit 1;;
 esac
done

if [ 1 -eq ${BROKEN_ONLY} ]
then
	echo "The following hosts require manual error correction:"
	for LF in *.log; 
	do
		( echo $LF; \
	        MARK=$(grep MARK "${LF}" | awk '{print $2}' | tail -1); \
		sed -n "/${MARK}/,\$p" "${LF}" | grep -E 'dpkg: error' ) | grep -B1 blacklist | grep log | sed 's/\.log//g;'
	done 
	exit 0
fi

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
