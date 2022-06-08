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
IGNORE_CERT=0
CERTOPT=""
host=""
###

usage() {
        echo "${PROG} -[abchnrRDL] [-H host] [-d cmd.txt] [-f hosts.txt]"
        echo "choose one of"
        echo "	-a		  All hosts"
        echo "	-H [host]	  specific host"
        echo "	-d [commands.txt] debugging/alternate commands text"
        echo "  -f [hosts.txt]    alternate hosts file"
        echo "	-c		  connect test"
        echo "	-n		  no verification of host configuration with ${HOSTS}"
	echo "	-b                check for broken upgrades from last-run data"
	echo "	-r                reboot allowed hosts after update"
	echo "	-R                only list hosts that will reboot after update"
	echo "	-D                only list hosts that are currently disabled"
	echo "	-L                list all hosts configured hosts"
	echo "	-I                ignore host certificate errors (DANGEROUS)"
        echo "	-h		  this help text"
        echo ""
}

do_host() {
	host=${1}

	if [ 1 -eq ${VALIDATE} ]
	then
		thost=$(grep -wi "$host" ${HOSTS} | grep -viE "%.*$host" | egrep -v '^[[:space:]]*#')
		[[ -n "${thost}" ]] && host=${thost}
	fi

	host=${host%%[	# ]*}	# trailing tabs, hashes, and spaces go buh-bye

	if [ -n "${host}" -a -z "${host##*%*}" ]
	then
		# fuser@host-f%puser@host-p.example.net:redhat:X

		finalhost=${host%%%*}		# fuser@host-f
		[[ -z "${finalhost##*@*}" ]] && user=${finalhost%%@*}	# fuser

		jump=${host##*%}	# puser@host-p.example.net:redhat:X

		[[ -z "${jump##*:*}" ]] && distro=${jump#*:} && distro=${distro%%:*}
		[[ -n "${jump//*$distro:/}" ]] && reboot=${jump//*$distro:/}

		jump=${jump%%:*}	# puser@host-p.example.net
		host=$finalhost		# host-f
	else
		jump=""
		[[ -z "${host##*@*}" ]] && user=${host%%@*}
		host=${host##*@}
		[[ -z "${host##*:*}" ]] && distro=${host#*:} && distro=${distro%%:*}
		[[ -n "${host//*$distro:/}" ]] && reboot=${host//*$distro:/}
		host=${host%%:*}
	fi

	MYCMDS=${CMDS}${distro:+.$distro}
	[[ -n "${DCMDS}" ]] && MYCMDS=${DCMDS}

	echo "host: ${host}, user: ${user}, jump: ${jump:-none}, distro: ${distro:-generic}, commands: ${MYCMDS}"

	[[ "${distro:-generic}" = "disabled" ]] && return

	[[ ${IGNORE_CERT} -eq 1 ]] && CERTOPT="-o StrictHostKeyChecking=false -o UserKnownHostsFile=/dev/null -E /dev/null"

	SSHOPTS="-o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o IdentitiesOnly=yes -o ConnectTimeout=5 ${CERTOPT}"
	SSHIDS="-i ${HOME}/.ssh/id_rsa.puppeteer -i ${HOME}/.ssh/id_ecdsa.puppeteer"

	user=${user:-root}

	if [ "${host,,}" = "localhost" -o "${host}" = "127.0.0.1" -o "${host,,}" = "${MYHOST,,}" ]
	then

		if [ 1 -eq ${CONNECT_ONLY} ]
		then
			echo "testing local escalation"
			sudo whoami
		else
			echo "MARK --${DATE}-- host: ${host}, user: ${user}, jump: ${jump:-none}, distro: ${distro:-generic}, commands: ${MYCMDS}" >> ${host}.log
			sudo -i -u root -- < ${MYCMDS} | tee -a ${host}.log
			# we don't reboot localhost
		fi
	else
		if [ 1 -eq ${CONNECT_ONLY} ]
		then
			ssh -v ${SSHOPTS} ${SSHIDS} ${jump:+-J $user@$jump} ${user}@${host}
		else
			echo "MARK --${DATE}-- host: ${host}, user: ${user}, jump: ${jump:-none}, distro: ${distro:-generic}, commands: ${MYCMDS}" >> ${host}.log
			ssh ${SSHOPTS} ${SSHIDS} ${jump:+-J $user@$jump} ${user}@${host} < ${MYCMDS} 2>&1 | tee -a ${host}.log
			if [ "${reboot:-X}" = "R" -o \( "${reboot}" = "r" -a ${DO_REBOOT:-0} -eq 1 \) ]
			then
 				ssh ${SSHOPTS} ${SSHIDS} ${jump:+-J $user@$jump} ${user}@${host} "shutdown -r now" 2>&1 | tee -a ${host}.log
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

show_hosts() {
      (
	echo "HOSTNAME SYSTEM STATUS REBOOT"
	echo "-------- ------ ------ ------" 

	for line in $( grep -v '^#' ${HOSTS} | awk '{print $1}' | sort -f -t: -k2 -k1 )
	do
		RUN="enabled"
		host=${line%%:*}
		OS=${line//$host:/}
		OS=${OS%%:*}
		boot=${line##*:}

		if [ "${OS}" = "disabled" ]
		then
			RUN="disabled"
			OS="n/a"
		fi

		[[ "${boot}" = "r" ]] && boot="optional"
		[[ "${boot}" = "R" ]] && boot="forced"
		[[ "${boot,,}" = "x" ]] && boot=""

		PRINT=0
		if [ \( ${BOOT_ONLY:-0} -eq 0 \) -a \( ${DISABLED_ONLY:-0} -eq 0 \) ]
		then
			PRINT=1
		
		elif [ ${BOOT_ONLY:-0} -eq 1 -a "${boot}" != "" -a "$RUN" != "disabled"  ]
		then
			PRINT=1

		elif [ ${DISABLED_ONLY:-0} -eq 1 -a "$RUN" = "disabled"  ]
		then
			PRINT=1
		fi

		if [ ${PRINT:-0} -eq 1 ]
		then
			echo "$host $OS $RUN $boot"
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


while getopts "IRDLbranchH:d:f:" param; do
 case $param in
  a) ALL=1 ;;
  b) BROKEN_ONLY=1;;
  c) CONNECT_ONLY=1;;
  H) HOST_ONLY=1; host=${OPTARG} ;;
  d) DCMDS=${OPTARG} ;;
  f) HOSTS=${OPTARG} ;;
  n) VALIDATE=0 ;;
  r) DO_REBOOT=1 ;;
  L) show_hosts; exit 0;;
  D) DISABLED_ONLY=1; show_hosts; exit 0;;
  R) BOOT_ONLY=1; show_hosts; exit 0;;
  I) IGNORE_CERT=1;;
  h|*) usage; exit 1;;
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

if [ ! -r "${HOSTS}" ]
then
	echo "Unable to read hosts file >${HOSTS}<"
	echo "use the example file to generate your own"
	exit 1
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
