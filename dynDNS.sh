#!/bin/bash
#
# Cron Task: UpdateDynDNS - A DynDNS check and synchronizing script
#
# Source configuration file
source /etc/cron.includes/conf.d/updatedyndns.conf

# Enable debug
DYNDNS_DEBUG=0

# Must use test domains during debug
if [ "${DYNDNS_DEBUG}" -eq 1 ];
then
	dyndns_domain=("test.dyndns.org")
fi

# Cache directory
dyndns_cachedir="/var/ddns"

# Define scriptname
SCRIPTNAME=$(basename $0)

# bail if temp file exists
[ -f /tmp/${SCRIPTNAME}.* ] && exit 666

# Send notice to syslog
. /etc/cron.includes/scripts/cronlogger.sh
cronLogger "Starting task: ${SCRIPTNAME}"

# Make temp file
TEMPFILE=$(mktemp /tmp/${SCRIPTNAME}.XXXXXX)
touch ${TEMPFILE}

# Include file mailer script:
#     mailFile.func.sh
#
# This is the first script executed by run-parts.
# Needs createCronLogFile to be defined.
. /etc/cron.includes/scripts/mailFile.func.sh
MailFileCreate "/tmp/cron.daily-$(date +%F).log"

## Begin script
echo "#############################################################################" >> ${mailFile}
if [ "${DYNDNS_DEBUG}" -eq 1 ];
then
	echo "# NOTICE: DEBUG Mode is enabled. Hosts will not updated." >> ${mailFile}
fi
echo "# $(pwd)/${SCRIPTNAME}" >> ${mailFile}
echo "# Started: $(date +%T) $(date +%x)" >> ${mailFile}
echo "#############################################################################" >> ${mailFile}
echoMailFile

# Veryify ddns cache directory
if [ ! -d "${dyndns_cachedir}" ];
then
	mkdir -p ${dyndns_cachedir}
fi

for host in "${dyndns_domain[@]}"
do
	# Set files for writing information
	dyndns_pre_ip="/var/ddns/previous-${host}.ip"
	dyndns_new_ip="/var/ddns/current-${host}.ip"
	dyndns_upd_ip="/var/ddns/updated-${host}.ip"
	dyndns_ip_timestamp="/var/ddns/ip-${host}.timestamp"

	# Verify previous IP file
	if [ ! -e ${dyndns_pre_ip} ];
	then
		echo 10.0.0.1 > ${dyndns_pre_ip}
	fi
	touch ${dyndns_pre_ip}

	# Fetch current IP address
	case "${dyndns_fetch_method}" in
	[Ww][Gg][Ee][Tt])
		wget -q ${dyndns_ip_check_host} --output-document=${dyndns_new_ip}
	;;
        [Cc][Uu][Rr][Ll])
		curl -s -o ${dyndns_new_ip} ${dyndns_ip_check_host}
	;;
	*);;
	esac

	case "${dyndns_use_https}" in
	[Yy][Ee][Ss])
		dyndns_query_url="https://members.dyndns.org:443/nic/update"
	;;
	*)
		dyndns_query_url="http://members.dyndns.org/nic/update"
	;;
	esac

	# Set new and previous IP addresses
	newip="$(cat ${dyndns_new_ip})"
	previp="$(cat ${dyndns_pre_ip})"

	# Script run timestamp
	echo "Host: ${host}" >> ${mailFile}
	echo "Checked: $(date)" >> ${mailFile}
	echo "HTTPS: ${dyndns_use_https}" >> ${mailFile}

	# DynDNS check
	if [ "${newip}" == "${previp}" ];
	then
		rm -f ${dyndns_new_ip}
		echo -e "nochg ${newip}\n" >> ${mailFile}
	else
		# Update IP address
		case "${dyndns_fetch_method}" in
		[Ww][Gg][Ee][Tt])
			wget -q \
			--user=${dyndns_username} \
			--password=${dyndns_password} \
			--output-document=${dyndns_upd_ip} \
			${dyndns_query_url}?hostname=${host}&myip=${newip}&offline=${dyndns_offline}
		;;
		[Cc][Uu][Rr][Ll])
			curl -s -o ${dyndns_upd_ip} --silent -u ${dyndns_username}:${dyndns_password} \
			${dyndns_query_url}?hostname=${host}&myip=${newip}&offline=${dyndns_offline}
		;;
		*);;
		esac

		rm -f ${dyndns_new_ip} ${dyndns_pre_ip}
		echo ${newip} > ${dyndns_pre_ip}
		echo -e "IP Updated: $(date)\n" >> ${mailFile}
	fi
done

## End script
echo "#############################################################################" >> ${mailFile}
echo "# $(pwd)/${SCRIPTNAME}" >> ${mailFile}
echo "# Terminated: $(date +%T) $(date +%x)" >> ${mailFile}
echo "#############################################################################" >> ${mailFile}
echoMailFile

# Delete temp file
rm ${TEMPFILE}

# Let cron daemon know progress
cronLogger "Task complete: ${SCRIPTNAME}"

exit 0

##
## EOF
##
