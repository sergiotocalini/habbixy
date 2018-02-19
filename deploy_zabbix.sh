#!/usr/bin/env ksh
SOURCE_DIR=$(dirname $0)
ZABBIX_DIR=/etc/zabbix

mkdir -p ${ZABBIX_DIR}/scripts/agentd/habbixy
cp ${SOURCE_DIR}/habbixy/map.index ${ZABBIX_DIR}/scripts/agentd/habbixy/
cp ${SOURCE_DIR}/habbixy/habbixy.conf.example ${ZABBIX_DIR}/scripts/agentd/habbixy/
cp ${SOURCE_DIR}/habbixy/habbixy.sh ${ZABBIX_DIR}/scripts/agentd/habbixy/
cp ${SOURCE_DIR}/habbixy/zabbix_agentd.conf ${ZABBIX_DIR}/zabbix_agentd.d/habbixy.conf
