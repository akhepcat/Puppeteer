#!/bin/bash

COLUMNS=$(stty size | awk '{print $2}')

if [ -z "$1" ]
then
	echo "which host? "
	/bin/ls -C --width=${COLUMNS} *.log 2>/dev/null| sed 's/\.log//gi;'
	exit 1
fi

if [ -r "$1" ]
then
	MARK=$(grep MARK "${1}" | awk '{print $2}' | tail -1)

	sed -n "/${MARK}/,\$p" "${1}"
else
	echo "can't open logfile ${1}"
	exit 1
fi
