#!/bin/bash
#========================================================================
#   
#   File：：auto_lnmp.sh
#   Author：yangwendi
#   Date：2019/08/10
#   Description：下载安装 nginx1.9.9,MySQL5.7,PHP7.2,以此部署LNMP服务，
#            centos7.4-7.5可行，并且需要将80开启，如需要在外部访问数据库，
#           需要将3306端口开启
#
#========================================================================
dir=/data  
# 公共函数
[ -f /etc/init.d/functions ] && . /etc/init.d/functions || exit 1
# 创建放置所有下载文件的目录
createDir() {
  if [[ ! -e $dir ]]
    then
      mkdir $dir
  else
    echo "文件下载目录已存在！"
  fi
}
# 安装nginx1.9.9
installNginx() {
  echo  "开始安装Nginx服务，请稍后..."
  # 安装一些需要的依赖，供以后的安装软件使用
  yum install -y net-tools wget pcre pcre-devel openssl openssl-devel gcc make gcc-c++ &>/dev/null
  # 进入放置下载文件的目录
  [[ -e $dir ]] && cd $dir
  # 下载 Nginx1.9.9 压缩包
  wget http://nginx.org/download/nginx-1.9.9.tar.gz &>/dev/null
  if [ -f 'nginx-1.9.9.tar.gz' ];then
    # 解压缩 nginx1.9.9 压缩包，并进入解压后的文件目录里
    tar -zxvf nginx-1.9.9.tar.gz &>/dev/null && cd nginx-1.9.9
    # 编译，所有配置默认
    ./configure &>/dev/null
    [ $(echo $?) -eq 0 ] && make &>/dev/null && make install &>/dev/null
    [ $(echo $?) -eq 0 ] && rm -rf nginx* && echo "nginx1.9.9 安装成功"
  fi
}
# 对nginx进行配置
configureNginx() {
  config_path="/usr/local/nginx/conf/nginx.conf"
  if [[ -f $config_path ]]
    then
      # 如果文件目录存在，则在文件最后一行写入include
      config_line=`sed -n '$=' ${config_path}`
      # 创建放置nginx配置文件的目录，并给予权限
      mkdir /usr/local/nginx/myConf && chmod 755 /usr/local/nginx/myConf
      sed -i "${config_line}i\include /usr/local/nginx/myConf/*.conf;" $config_path
  fi  
}
# 开启nginx，并设置成开机自启模式
startNginx() {
  echo "正在启动nginx服务，请稍等..."
  # 检查配置文件语法
  /usr/local/nginx/sbin/nginx -t
  # 开启
  if [[ $(echo $?) -eq 0 ]]
    then
      /usr/local/nginx/sbin/nginx
      if [ $(netstat -lutnp|grep 80|wc -l) -eq 1 ]
        then
          action "nginx 已成功启动！" /bin/true
      else
        echo "nginx 开启失败，请人工检查服务端口是否冲突或其他问题！！！"
      fi
  fi
}
installMysql() {
  echo "正在安装MySQL5.7，请稍等..."
  # 由于CentOS 的yum源中没有mysql5.7，需要到mysql的官网下载yum repo配置文件。
  wget https://dev.mysql.com/get/mysql57-community-release-el7-9.noarch.rpm &>/dev/null
  # 然后进行repo的安装
  rpm -ivh mysql57-community-release-el7-9.noarch.rpm &>/dev/null
  # 安装mysql5.7
  yum install mysql-server mysql-devel -y &>/dev/null
  if [[ -f /etc/my.cnf ]];then
    systemctl start mysqld
   else
     echo "MySQL安装失败！！！！"
     exit 1
  fi
  cat << EOF > /etc/my.cnf    
[mysqld]      
default_password_lifetime=0 
EOF
  # 使用openssl生成8位的高强度密码，必须安装OpenSSL库
  sha_passwd=`openssl rand -base64 8`
  # 获取临时密码，用于修改密码
  oo=`grep 'temporary password' /var/log/mysqld.log | awk '{print $11}'`
  mysql_file=`whereis mysql | awk '{print $2}'`
  ${mysql_file} -uroot -p${oo} -b --connect-expired-password <<EOF
SET PASSWORD = PASSWORD('${sha_passwd}');
grant all privileges on *.* to root@'%' identified by '${sha_passwd}';
EOF
  if [[ "$?" -eq 0 ]];then
    action "MySQL数据库安装成功,密码为:${sha_passwd}" /bin/true
  else
    action "MySQL数据库安装失败密码初始化失败！" /bin/false
    exit 1
  fi
}
# 重启 mysql_server
startMysql(){
  # restart
  systemctl restart mysqld   
  if [[ $(netstat -lutnp|grep 3306|wc -l) -eq 1 ]]
    then
      action "mysql 开启服务成功..."  /bin/true
  else
    echo "mysql 启动失败，请检查服务！！！"
  fi
}
installPHP() {
  # 为了防止centos上发生php冲突
  yum -y remove php* &>/dev/null
  echo "开始更新PHP7.2 repo..."
  rpm -Uvh https://dl.fedoraproject.org/pub/epel/7/x86_64/Packages/e/epel-release-7-11.noarch.rpm &>/dev/null
  rpm -Uvh https://mirror.webtatic.com/yum/el7/webtatic-release.rpm  &>/dev/null
  if [[ "$?" -eq 0 ]];then
    action "php7.2 repo 已经更新成功！！！！" /bin/true
  else
    action "php7.2 repo 已经更新失败！！！！" /bin/false
    exit 1
  fi
  echo "开始安装php7.2 ..."
  # 安装php7.2所需要的依赖及组件
  yum -y install php72w php72w-cli php72w-fpm php72w-common php72w-devel php72w-embedded php72w-gd php72w-mbstring php72w-mysqlnd php72w-opcache php72w-pdo php72w-xml &>/dev/null
  if [[ "$?" -eq 0 ]];then
    action "php7.2 已经安装成功！！！！" /bin/true
  else
    action "php7.2 已经安装失败！！！！" /bin/false
    exit 1
  fi
}
# start php-fpm
startPhpfpm(){
  # start
  systemctl enable php-fpm.service
  systemctl start php-fpm.service
  if [[ $(netstat -lutnp|grep 9000|wc -l) -eq 1 ]]
    then
      action "php-fpm 启动成功..." /bin/true
  else
    echo "php-fpm 启动失败，请检查服务！！！"
  fi
}
main() {
  createDir
  installNginx
  sleep 3
  startNginx
  sleep 2
  installMysql
  sleep 3
  startMysql
  sleep 2
  installPHP
  startPhpfpm
}
main
