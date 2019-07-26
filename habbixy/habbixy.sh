#!/usr/bin/env ksh
PATH=/usr/local/bin:${PATH}
IFS_DEFAULT=${IFS}

#################################################################################

#################################################################################
#
#  Variable Definition
# ---------------------
#
APP_NAME=$(basename $0)
APP_DIR=$(dirname $0)
APP_VER="0.0.1"
APP_WEB="http://www.sergiotocalini.com.ar/"
APP_TIMESTAMP=`date '+%s'`
APP_MAP_INDEX=${APP_DIR}/map.index
HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
HAPROXY_SOCKET="/var/run/haproxy.sock"
HAPROXY_CACHE_DIR=${APP_DIR}/var
HAPROXY_CACHE_TTL=5                                      # IN MINUTES
#
#################################################################################

#################################################################################
#
#  Load Environment
# ------------------
#
[[ -f ${APP_DIR}/${APP_NAME%.*}.conf ]] && . ${APP_DIR}/${APP_NAME%.*}.conf

#
#################################################################################

#################################################################################
#
#  Function Definition
# ---------------------
#
usage() {
    echo "Usage: ${APP_NAME%.*} [Options]"
    echo ""
    echo "Options:"
    echo "  -a            Query arguments."
    echo "  -h            Displays this help message."
    echo "  -j            Jsonify output."
    echo "  -s ARG(str)   Section (default=stat)."
    echo "  -v            Show the script version."
    echo ""
    echo "Please send any bug reports to sergiotocalini@gmail.com"
    exit 1
}

version() {
    echo "${APP_NAME%.*} ${APP_VER}"
    exit 1
}

check_params() {
    [[ -d ${HAPROXY_CACHE_DIR} ]] || mkdir -p ${HAPROXY_CACHE_DIR}
}

refresh_cache() {
    type=${1:-'stat'}
    file=${HAPROXY_CACHE_DIR}/${type}.cache
    if [[ $(( `stat -c '%Y' "${file}"`+60*${HAPROXY_CACHE_TTL} )) -le ${APP_TIMESTAMP} ]]; then
	echo "show ${type}" | sudo socat ${HAPROXY_SOCKET} stdio 2>/dev/null > ${file}
    fi
    echo "${file}"
    return 0
}

discovery() {
    svname=${1}
    if [[ ${svname} =~ (BACKEND|FRONTEND) ]]; then
	cache=$(refresh_cache 'stat')
 	for item in `cat ${cache} | awk -F"," '$2 ~ /^'${svname}'$/{print}' | cut -d, -f1 | sort | uniq`; do
	    echo ${item}
        done
    elif [[ ${svname} == "certs" ]]; then
	discovery_certs
    fi
}

ifArrayHas() {
    item=${1}
    shift
    array=( "${@}" )
    for i in ${!array[@]}; do
	[[ ${array[${i}]} == ${item} ]] && return 0
    done
    return 1
}

discovery_certs() {
    while read line; do
	IFS=" " params=( ${line} )
	IFS=${IFS_DEFAULT}
	for idx in ${!params[@]}; do
	    if [[ ${params[${idx}]} == 'crt' ]]; then
		if ! ifArrayHas "${params[$((${idx}+1))]}" "${crt[@]}"; then
		    if [[ -f "${params[$((${idx}+1))]}" ]]; then
			crt[${#crt[@]}]="${params[$((${idx}+1))]}"
		    fi
		fi
	    elif [[ ${params[${idx}]} == 'crt-list' ]]; then
		if ! ifArrayHas "${params[$((${idx}+1))]}" "${crt_list[@]}"; then
		    if [[ -f "${params[$((${idx}+1))]}" ]]; then
			crt_list[${#crt_list[@]}]="${params[$((${idx}+1))]}"
		    fi
		fi
	    fi
	done
    done < <(grep -E "(^|\s)bind($|\s)" ${HAPROXY_CONFIG} | grep -E " (crt|crt-list) " | awk '{$1=$1};1')
    for idx in ${!crt_list[@]}; do
	while read cert; do
	    if ! ifArrayHas "${cert}" "${crt[@]}"; then
		if [[ -f "${cert}" ]]; then
		    crt[${#crt[@]}]="${cert}"
		fi
	    fi
	done < <(cat ${crt_list[${idx}]})
    done
    printf '%s\n' ${crt[@]}
}

get_cert() {
    file="${1}"
    attr="${2}"

    [ -f ${file} ] || return 1
    
    if [[ ${attr} == 'expires' ]]; then
	after=`sudo openssl x509 -noout -in ${file} -enddate 2>/dev/null|cut -d'=' -f2`
	res=$((($(date -d "${after}" +'%s') - $(date +'%s'))/86400))
    fi
    echo "${res:-0}"
    return 0    
}

get_cert_text() {
    crt_file="${1}"

    [[ -f ${crt_file} ]] || return 1
    
    openssl x509 -noout -in ${crt_file} -text
    return 0
}

get_stat() {
    pxname=${1}
    svname=${2}
    stats=${3}

    cache=$(refresh_cache 'stat')
    
    _STAT=`grep :${stats}: ${APP_MAP_INDEX}`
    _INDEX=${_STAT%%:*}
    _DEFAULT=${_STAT##*:}

    _res="`grep \"${pxname},${svname}\" \"${cache}\" 2>/dev/null`"
    
    _res="$(echo $_res | cut -d, -f ${_INDEX})"
    if [ -z "${_res}" ] && [[ "${_DEFAULT}" != "@" ]]; then
	echo "${_DEFAULT}"
    else
	echo "${_res}"
    fi
}

get_info() {
    attr=${1}

    cache=$(refresh_cache 'info')
    
    _res="`grep -E \"^${attr}:\" \"${cache}\" 2>/dev/null | cut -d: -f 2`"
    echo "${_res:-0}"
}
#
#################################################################################

#################################################################################
while getopts "s::a:s:uphvj:" OPTION; do
    case ${OPTION} in
	h)
	    usage
	    ;;
	s)
	    SECTION="${OPTARG}"
	    ;;
        j)
            JSON=1
            IFS=":" JSON_ATTR=(${OPTARG})
	    IFS=${IFS_DEFAULT}
            ;;
	a)
	    ARGS[${#ARGS[*]}]=${OPTARG//p=}
	    ;;
	v)
	    version
	    ;;
         \?)
            exit 1
            ;;
    esac
done

if [[ ${JSON} -eq 1 ]]; then
    rval=$(discovery ${ARGS[*]})
    echo '{'
    echo '   "data":['
    count=1
    while read line; do
        IFS="|" values=(${line})
        output='{ '
        for val_index in ${!values[*]}; do
            output+='"'{#${JSON_ATTR[${val_index}]}}'":"'${values[${val_index}]}'"'
            if (( ${val_index}+1 < ${#values[*]} )); then
                output="${output}, "
            fi
        done 
        output+=' }'
        if (( ${count} < `echo ${rval}|wc -l` )); then
            output="${output},"
        fi
        echo "      ${output}"
        let "count=count+1"
    done <<< ${rval}
    echo '   ]'
    echo '}'
else
    if [[ ${SECTION} == 'stat' ]]; then
	rval=$( get_stat ${ARGS[*]} )
	rcode="${?}"
    elif [[ ${SECTION} == 'info' ]]; then
	rval=$( get_info ${ARGS[*]} )
	rcode="${?}"
    elif [[ ${SECTION} == 'certs' ]]; then
	rval=$( get_cert ${ARGS[*]} )
    fi
    echo ${rval:-0}
fi
exit ${rcode}
