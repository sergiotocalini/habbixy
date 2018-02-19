#!/usr/bin/env ksh
rcode=0
PATH=/usr/local/bin:${PATH}

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
HAPROXY_SOCKET="/var/run/haproxy.sock"
HAPROXY_CACHE_DIR=${APP_DIR}/var
HAPROXY_CACHE_STAT=${HAPROXY_CACHE_DIR}/stat.cache
HAPROXY_CACHE_INFO=${HAPROXY_CACHE_DIR}/info.cache
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
    echo "  -s ARG(str)   Script."
    echo "  -v            Show the script version."
    echo ""
    echo "Please send any bug reports to sergiotocalini@gmail.com"
    exit 1
}

version() {
    echo "${APP_NAME%.*} ${APP_VER}"
    exit 1
}

refresh_cache() {
    local type=${1:-'stat'}
    local file=${HAPROXY_CACHE_DIR}/${type}.cache
    if [[ $(( `stat -c '%Y' "${file}"`+60*${HAPROXY_CACHE_TTL} )) -ge ${APP_TIMESTAMP} ]]; then
	echo "show ${type}" | socat ${HAPROXY_SOCKET} stdio 2>/dev/null > ${file}
    fi
}

discovery() {
    refresh_cache 'stat'
    for item in `grep ${1} ${HAPROXY_CACHE_STAT} | cut -d, -f1 | uniq`; do
	echo ${item}
    done
}

get_stat() {
    pxname=${1}
    svname=${2}
    stats=${3}

    refresh_cache 'stat'
    
    _STAT=`grep :${stats}: ${APP_MAP_INDEX}`
    _INDEX=${_STAT%%:*}
    _DEFAULT=${_STAT##*:}

    _res="`grep \"${pxname},${svname}\" \"${HAPROXY_CACHE_STAT}\"`"
    
    _res="$(echo $_res | cut -d, -f ${_INDEX})"
    if [ -z "${_res}" ] && [[ "${_DEFAULT}" != "@" ]]; then
	echo "${_DEFAULT}"
    else
	echo "${_res}"
    fi
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
	    SCRIPT="${APP_DIR}/scripts/${OPTARG}"
	    ;;
        j)
            JSON=1
            IFS=":" JSON_ATTR=(${OPTARG})
            ;;
	a)
	    SCRIPTS_ARGS[${#SCRIPTS_ARGS[*]}]=${OPTARG}
	    ;;
	v)
	    version
	    ;;
         \?)
            exit 1
            ;;
    esac
done

count=1
for arg in ${SCRIPTS_ARGS[@]}; do
    ARGS+="${arg//p=} "
    let "count=count+1"
done

#if [[ -f "${SCRIPT%.sh}.sh" ]]; then
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
	rval=`${SCRIPT%.sh}.sh ${ARGS} 2>/dev/null`
	rcode="${?}"
	echo ${rval:-0}
    fi
#else
#    echo "ZBX_NOTSUPPORTED"
#    rcode="1"
#fi

exit ${rcode}
