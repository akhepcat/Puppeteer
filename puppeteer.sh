#!/bin/bash
PROG="${0##*/}"
DATE="$(date +%Y%m%d-%H%M)"
HOSTS=puppeteer.hosts
CMDS=puppeteer.commands
###
MYHOST=$(hostname)

CONNECT_ONLY=0
ALL=0
VALIDATE=1
DO_REBOOT=0
host=""
###

usage() {
        echo "${PROG} -[abcnr] [-h host] [-d cmd.txt]"
        echo "choose one of"
        echo "	-a		  All hosts"
        echo "	-h [host]	  specific host"
        echo "	-d [commands.txt] debugging/alternate commands text"
        echo "	-c		  connect test"
	echo "	-b                check for broken upgrades from last-run data"
	echo "	-r                reboot allowed hosts after update"
	echo "	-R                only list hosts that will reboot after update"
        echo "	-n		  no verification of host configuration with ${HOSTS}"
        echo ""
}

do_host() {
	host=${1}

	if [ 1 -eq ${VALIDATE} ]
	then
		thost=$(grep -wi "$host" ${HOSTS} | grep -v '^#')
		[[ -n "${thost}" ]] && host=${thost}
	fi

	host=${host%%[	# ]*}	# trailing tabs, hashes, and spaces go buh-bye
	[[ -z "${host##*@*}" ]] && user=${host%%@*}
	host=${host##*@}
	[[ -z "${host##*:*}" ]] && distro=${host#*:} && distro=${distro%%:*}
	[[ -n "${host//*$distro:/}" ]] && reboot=${host//*$distro:/}
	host=${host%%:*}

	MYCMDS=${CMDS}${distro:+.$distro}
	[[ -n "${DCMDS}" ]] && MYCMDS=${DCMDS}

	echo "host: ${host}, user: ${user:-root}, distro: ${distro:-generic}, commands: ${MYCMDS}"

	[[ "${distro:-generic}" = "disabled" ]] && return

	SSHOPTS="-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o IdentitiesOnly=yes -o ConnectTimeout=5"
	SSHIDS="-i ${HOME}/.ssh/id_rsa.puppeteer -i ${HOME}/.ssh/id_ecdsa.puppeteer"

	if [ "${host,,}" = "localhost" -o "${host}" = "127.0.0.1" -o "${host,,}" = "${MYHOST,,}" ]
	then

		if [ 1 -eq ${CONNECT_ONLY} ]
		then
			echo "testing local escalation"
			sudo whoami
		else
			echo "MARK --${DATE}-- host: ${host}, user: ${user:-root}, distro: ${distro:-generic}, commands: ${MYCMDS}" >> ${host}.log
			sudo -i -u root -- < ${MYCMDS} | tee -a ${host}.log
			# we don't reboot localhost
		fi
	else
		if [ 1 -eq ${CONNECT_ONLY} ]
		then
			ssh -4 -v ${SSHOPTS} ${SSHIDS} ${user:-root}@${host}
		else
			echo "MARK --${DATE}-- host: ${host}, user: ${user:-root}, distro: ${distro:-generic}, commands: ${MYCMDS}" >> ${host}.log
			ssh -4 ${SSHOPTS} ${SSHIDS} ${user:-root}@${host} < ${MYCMDS} 2>&1 | tee -a ${host}.log
			if [ "${reboot:-X}" = "R" -o \( "${reboot}" = "r" -a ${DO_REBOOT:-0} -eq 1 \) ]
			then
 				ssh -4 ${SSHOPTS} ${SSHIDS} ${user:-root}@${host} "shutdown -r now" 2>&1 | tee -a ${host}.log
			fi
		fi
	fi

	echo "complete"
	echo ""

	unset user
	unset distro
}

all_hosts() {

	for host in $(grep -v '^#' ${HOSTS});
	do
		do_host ${host}
	done
}
show_rebooters() {
      (
	echo "HOSTNAME REBOOT" ;
	echo "-------- ------" ; 

	for line in $(grep -Ei ':r(\s+|$)' ${HOSTS} | awk '{print $1}')
	do
		if [ "${line##*disabled*}" = "$line" ]
		then
			host=${line%%:*} ;
			boot=${line##*:} ;

			[[ "${boot}" = "r" ]] && boot="optional" || boot="forced" ;

			echo "$host $boot"
		fi
	done
      ) | column -t
	echo ""
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


while getopts "rRbanch:d:" param; do
 case $param in
  a) ALL=1 ;;
  b) BROKEN_ONLY=1;;
  c) CONNECT_ONLY=1;;
  h) HOST_ONLY=1; host=${OPTARG} ;;
  d) DCMDS=${OPTARG} ;;
  n) VALIDATE=0 ;;
  r) DO_REBOOT=1 ;;
  R) show_rebooters; exit 0;;
  *) usage; exit 1;;
 esac
done

if [ 1 -eq ${BROKEN_ONLY:-0} ]
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
