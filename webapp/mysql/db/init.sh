#!/bin/bash
set -xe
set -o pipefail

CURRENT_DIR=$(cd $(dirname $0);pwd)
export MYSQL_HOST=${MYSQL_HOST:-10.162.86.102}
export MYSQL_PORT=${MYSQL_PORT:-3306}
export MYSQL_USER=${MYSQL_USER:-isucon}
export MYSQL_DBNAME=${MYSQL_DBNAME:-isuumo}
export MYSQL_PWD=${MYSQL_PASS:-isucon}
export LANG="C.UTF-8"
cd $CURRENT_DIR

cat *.sql | mysql --defaults-file=/dev/null -h $MYSQL_HOST -P $MYSQL_PORT -u $MYSQL_USER $MYSQL_DBNAME
