#!/bin/bash

COLUMNS=$(stty size | awk '{print $2}')

if [ -z "$1" ]
then
	echo "which host? "
	/bin/ls -C --width=${COLUMNS} *.log 2>/dev/null | sed 's/\.log//gi;'
	exit 1
fi

if [ -r "$1" ]
then
	LF=${1}
elif [ -r "${1}.log" ]
then
	LF="${1}.log"
else
	LF=""
fi

if [ -n "${LF}" ]
then
	MARK=$(grep MARK "${LF}" | awk '{print $2}' | tail -1)

	sed -n "/${MARK}/,\$p" "${LF}"
else
	echo "can't open logfile ${LF:-$1}"
	exit 1
fi
