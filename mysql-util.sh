#!/bin/bash


if [ ! -d /var/lib/r1soft/sandbox ]
then
mkdir -p -m 700 /var/lib/r1soft/sandbox
fi

workdir=/var/lib/r1soft/sandbox

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [ ! -d ${workdir}/mysql ]
then
dbinstall=1
else
dbinstall=0
fi


sock_mycnf() {
if [ -f ${workdir}/my.cnf ]
then
rm -f ${workdir}/my.cnf
fi
echo "Creating my.cnf for temporary (sandbox) instance ..."
cat > $workdir/my.cnf << EOF
[mysqld]
#innodb_force_recovery = 6
skip-networking
datadir=$workdir
socket=$workdir/mysql.sock
innodb_data_home_dir=$workdir
innodb_data_file_path=ibdata1:10M:autoextend
innodb_log_group_home_dir=$workdir
innodb_log_files_in_group=2
[mysql.server]
user=mysql
basedir=$workdir
[mysqld_safe]
log-error=$workdir/mysqld.log
pid-file=$workdir/mysqld.pid
EOF
}

nopass_mycnf() {
if [ -f ${workdir}/my.cnf ]
then
rm -f ${workdir}/my.cnf
fi
echo "Creating my.cnf for temporary (sandbox) instance ..."
cat > $workdir/my.cnf << EOF
[mysqld]
#innodb_force_recovery = 6
skip-networking
datadir=$workdir
socket=$workdir/mysql.sock
innodb_data_home_dir=$workdir
innodb_data_file_path=ibdata1:10M:autoextend
innodb_log_group_home_dir=$workdir
innodb_log_files_in_group=2
skip-grant-tables
[mysql.server]
user=mysql
basedir=$workdir
[mysqld_safe]
log-error=$workdir/mysqld.log
pid-file=$workdir/mysqld.pid
EOF
}

net_mycnf() {
if [ -f ${workdir}/my.cnf ]
then
rm -f ${workdir}/my.cnf
fi
echo "Creating my.cnf for temporary (sandbox) instance ..."
cat > $workdir/my.cnf << EOF
[mysqld]
#innodb_force_recovery = 6
datadir=$workdir
socket=$workdir/mysql.sock
innodb_data_home_dir=$workdir
innodb_data_file_path=ibdata1:10M:autoextend
innodb_log_group_home_dir=$workdir
innodb_log_files_in_group=2
port=3307
bind-addr=0.0.0.0
[mysql.server]
user=mysql
basedir=$workdir
[mysqld_safe]
log-error=$workdir/mysqld.log
pid-file=$workdir/mysqld.pid
EOF
}

installdb() {
if [ $dbinstall -eq 1 ]
then
echo "Installing mysql structure in ${workdir} ..."
mysql_install_db --datadir=${workdir} > /dev/null 2>&1
return_value=$?
else
echo "Found mysql structure in ${workdir} ..."
fi
exitstatus
}

logcreate() {
if [ ! -f "${workdir}/mysqld.log" ]
then
echo "Creating empty logfile ..."
touch ${workdir}/mysqld.log
else
echo "Found existing logfile in  ${workdir} ..."
fi
}

permset() {
echo "Setting ownerships and permissions ..."
chown -R mysql.mysql $workdir

for dir in $( find $workdir -type d )
do
chmod 700 $dir
done

for file in $( find $workdir -type f )
do
chmod 660 $file
done
}

startinstance() {
echo "Starting mysql sandbox instance ..."
mysqld_safe --defaults-file=${workdir}/my.cnf &
return_value=$?
sleep 5
exitstatus
}

securitycheck() {
if [ -d /sys/module/apparmor ]
then
echo "apparmor installation found ..."
aa-status --enabled
return_value=$?
else
echo "no apparmor policies are loaded ..."
fi

if [ $return_value -eq 0 ]
then
echo "apparmor is running checking profiles ..."
grep mysqld /sys/kernel/security/apparmor/profiles >/dev/null 2>&1
return_value=$?
fi

if [ $return_value -eq 0 ]
then
echo "Mysql profile detected ..."
echo "Please disable apparmor"
exit 4
fi

}

exitstatus() {
if [ $? -eq  0 ]
then
echo "Success ..."
else
echo "Oops there was a problem grabbing logs."
echo "=============================================================="
agentlogs
exit 1
fi
}

setpass() {
while true; do
    read -p "Would you like to set a password? [Y/N]: " ny
        case $ny in
        [Yy]* ) read -p "Is this instance currently password protected? [Y/N]: " yn
                        case $yn in
                        [Yy]* ) echo -n "Enter current password and press [ENTER]: "
                                        read -s cpass
                                        echo
                    echo -n "Enter new password and press [ENTER]: "
                                        read -s npass
                                        echo
                                        mysql -u root -p${cpass} -S${workdir}/mysql.sock -e "update mysql.user set Password=PASSWORD('${npass}') where user='root';" 2>&1
                                        mysql -u root -p${cpass} -S${workdir}/mysql.sock -e "flush privileges;" 2>&1
                    break;;

                        [Nn]* ) echo -n "Enter a new password and press [ENTER]: "
                                        read -s pass
                                        echo
                                        mysql -S${workdir}/mysql.sock -e "update mysql.user set Password=PASSWORD('${pass}') where user='root';" 2>&1
                                        mysql -S${workdir}/mysql.sock -e "flush privileges;" 2>&1
                                        break;;
                        * ) echo "Please answer yes or no.";;
                        esac;;
        [Nn]* ) break;;
        esac
        done
}

stopinstance() {
if [ -f ${workdir}/mysqld.pid ]
then
pid=$(cat ${workdir}/mysqld.pid)
echo "Stopping (sandbox) instance .."
kill $pid
sleep 5
else
echo "No (sandbox) instance running"
fi
}

myisamchk() {
echo "Running Database Repair ..."
if [ -f ${workdir}/mysqld.pid ]
then
echo "Sandbox instance is running ..."
stopinstance
find ${workdir} -name '*.MYI' -exec myisamchk -r {} \;
find ${workdir} -name '*.MYI' -exec myisamchk -o {} \;
echo "Success"
fi
}

 agentlogs() {
echo -n "-- making tmp directory "
TMP=`mktemp -d /tmp/r1soft-report-XXXXXX`
echo "done."

echo "=============================================================="
echo "using: ${TMP}"

if [ -f ${workdir}/mysqld.log ]
then
echo -n "-- getting '${workdir}/mysqld.log' "
cat ${workdir}/mysqld.log 2>${TMP}/mysql.error | gzip -9 > ${TMP}/mysqld.log.gz
rm -f ${TMP}/mysql.error
echo "done."
fi

if [ -f ${workdir}/my.cnf ]
then
echo -n "-- getting '${workdir}/my.cnf' "
cat ${workdir}/my.cnf > ${TMP}/my.cnf 2>&1
echo "done."
fi

if [ -f /var/log/messages ]
then
echo -n "-- getting '/var/log/messages' "
cat /var/log/messages 2>${TMP}/messages.error | gzip -9 >  ${TMP}/messages.gz
rm -f ${TMP}/messages.error
echo "done."
fi

if [ -f /var/log/syslog ]
then
echo -n "-- getting '/var/log/syslog' "
cat /var/log/messages 2>${TMP}/syslog.error | gzip -9 >  ${TMP}/syslog.gz
rm -f ${TMP}/syslog.error
echo "done."
fi

echo -n "-- getting 'MySQL Version' "
mysql --version > ${TMP}/mysqlversion 2>&1
echo "done."

echo -n "-- getting '/proc/partitions' "
cat /proc/partitions > ${TMP}/partitions 2>&1
echo "done. "

echo -n "-- getting 'fdisk -l' "
fdisk -l > ${TMP}/fdisk 2>&1
echo "done."

echo -n "-- getting 'cdp -v' "
/usr/sbin/r1soft/bin/cdp -v > ${TMP}/cdp 2>&1
echo "done."

echo -n "-- getting 'ls -la /lib/modules/r1soft' "
ls -la /lib/modules/r1soft > ${TMP}/modules 2>&1
echo "done."

echo -n "-- getting 'date' "
date > ${TMP}/date 2>&1
echo "done."

echo -n "-- getting 'uname -a' "
uname -a > ${TMP}/uname 2>&1
echo "done."

echo -n "-- getting 'ls -la /dev' "
ls -la /dev > ${TMP}/dev 2>&1
echo "done."

echo -n "-- getting 'lsmod' "
lsmod > ${TMP}/lsmod 2>&1
echo "done."

echo -n "-- getting 'ifconfig -a' "
ifconfig -a > ${TMP}/ifconfig 2>&1
echo "done."

echo -n "-- getting 'route -n' "
route -n > ${TMP}/route 2>&1
echo "done."

echo -n "-- getting 'netstat -anp' "
netstat -anp > ${TMP}/netstat 2>&1
echo "done."

echo -n "-- getting 'ps -auxf' "
ps auxf > ${TMP}/ps 2>&1
echo "done."

echo -n "-- getting 'w' "
w > ${TMP}/w 2>&1
echo "done."

echo -n "-- getting 'cat /proc/mounts' "
cat /proc/mounts > ${TMP}/mounts 2>&1
echo "done."

echo -n "-- getting 'df' "
df > ${TMP}/df 2>&1
echo "done."

echo -n "-- getting 'dmesg' "
dmesg > ${TMP}/dmesg 2>&1
echo "done."

echo -n "-- getting 'cat /proc/version' "
cat /proc/version > ${TMP}/version 2>&1
echo "done."

echo -n "-- getting 'cat /proc/meminfo' "
cat /proc/meminfo > ${TMP}/meminfo 2>&1
echo "done."

echo -n "-- getting 'cat /proc/cpuinfo' "
cat /proc/cpuinfo > ${TMP}/cpuinfo 2>&1
echo "done."

echo -n "-- getting 'cat /proc/slabinfo' "
cat /proc/slabinfo > ${TMP}/slabinfo 2>&1
echo "done."

echo -n "-- getting '/usr/sbin/r1soft/log/cdp.log' "
cat /usr/sbin/r1soft/log/cdp.log 2>${TMP}/cdplog.error | gzip -9 > ${TMP}/cdp.log.gz
rm -f ${TMP}/cdplog.error
echo "done."

echo -n "-- making tar file "
tar czfh "${TMP}.tar.gz" "${TMP}"
rm -rf ${TMP}

echo "=============================================================="
echo "Please attach this file to you support ticket."
echo
echo "file: ${TMP}.tar.gz"
echo
echo "=============================================================="
}

dump() {
for database in $(mysql -S ${workdir}/mysql.sock -BN -e "show databases"|grep -Ev 'mysql|test|information_schema|performance_schema'); do
echo "Found: $database"
echo "Dumping $database to: $database.sql ... "
mysqldump -S${workdir}/mysql.sock $database > ${workdir}/${database}.sql
done
return_value=$?
exitstatus
}

network_instance() {
stopinstance
securitycheck
installdb
net_mycnf
logcreate
permset
startinstance
setpass
echo "=============================================================="
echo
echo "Don't forget to stop your instance when you are done."
echo
echo "You can now access your instance with the following command:"
echo "mysql -u root -p -S${workdir}/mysql.sock"
echo
echo "=============================================================="
}

sock_instance() {
stopinstance
securitycheck
installdb
sock_mycnf
logcreate
permset
startinstance
setpass
echo "=============================================================="
echo
echo "Don't forget to stop your instance when you are done."
echo
echo "You can now access your instance with the following command:"
echo "mysql -u root -p -S${workdir}/mysql.sock"
echo
echo "=============================================================="
}

instance_dump() {
stopinstance
securitycheck
installdb
nopass_mycnf
logcreate
permset
startinstance
dump
stopinstance
}

instance_recovery() {
if [ -f ${workdir}/my.cnf ]
then
stopinstance
sed -i 's/#innodb_force_recovery = 6/innodb_force_recovery = 6/g' ${workdir}/my.cnf > /dev/null 2>&1
securitycheck
installdb
logcreate
permset
startinstance
echo "=============================================================="
echo
echo "Don't forget to stop your instance when you are done."
echo
echo "You can now access your instance with the following command:"
echo "mysql -S${workdir}/mysql.sock"
echo
echo "=============================================================="
else
stopinstance
securitycheck
installdb
nopass_mycnf
sed -i 's/#innodb_force_recovery = 6/innodb_force_recovery = 6/g' ${workdir}/my.cnf > /dev/null 2>&1
logcreate
permset
startinstance
echo "=============================================================="
echo
echo "Don't forget to stop your instance when you are done."
echo
echo "You can now access your instance with the following command:"
echo "mysql -S${workdir}/mysql.sock"
echo
echo "=============================================================="
fi
}

case "$1" in
    --network-instance|-ni)
    network_instance
    ;;
    --socket-instance|-si)
    sock_instance
    ;;
    --stop-instance|-s)
    stopinstance
    ;;
    --dump-instance|-di)
    instance_dump
    ;;
        --recovery-instance|-ri)
    instance_recovery
    ;;
    --set-pass|-p)
    setpass
        ;;
        --agentlogs|-l)
        agentlogs
        ;;
        --myisamchk|-c)
        myisamchk
        ;;
  *)
    echo $"Usage: $0 {-ni|-si|-di|-ri|-s|-p|-c|-l}"
        echo "  -ni, --network-instance:        Start a Sandbox instance with networking."
        echo "  -si, --socket-instance:         Starts a Sandbox instance with no networking."
        echo "  -di, --dump-instance:           Starts a Sandbox instance that writes all databases to mysqldump."
        echo "  -ri, --recovery-instance:       Starts a Sandbox with innodb recovery mode 6."
        echo "  -s,  --stop-instance:           Stops a running Sandbox instances."
        echo "  -p,  --set-pass:                Sets root password for Sandbox instance."
        echo "  -c,  --myisamchk:               Repairs myisam tables in the Sandbox instance."
        echo "  -l,  --agentlogs                Gets full logs for tech-support."
    exit 2
esac


