#!/bin/bash

#================================================================
# 
# File：auto_opencart.sh
# Author：yangwendi
# Date：2019/08/12
# Description：Automated deployment of opencart3.0.3.2
#   自动化部署opencart3.0.3.2脚本，opencart是一个商场系统，这个自动
#   部署需要配合auto_lnmp.sh才行，其他lnmp或许行
# 
#================================================================

# 公共函数
[[ -f /etc/init.d/functions ]] && . /etc/init.d/functions || exit 1

cat <<END 
#===============================================#
#                                               #
#           opencart3 自动化部署选项             #
#                                               #
#          1.部署新的opencart3网站               #
#          2.修复部署网站二次打开报错             #
#     3.修复解压opencart3失败后，无法重新安装     #
#                                               #
#                                               #
#===============================================#
END

read  -p "请你输入一个数字:" NUM
expr $NUM + 1 &> /dev/null
if [[ "$?" -ne 0 ]];then
  action "对不起，请你输入整数！！！" /bin/false
  exit 1
elif [[ "$NUM" -eq 0 ]];then
  action "对不起，请你输入比0大的数字！！！" /bin/false
  exit 1
fi

# 放置下载文件的便量文件夹
dir=/data
# 定义一个网站根目录
webSite=/data
# 名称
name=opencart_

# 验证端口是否被占用，IP是否合法，验证mysql账户并且新建数据库
checkIP2Port() {
  # 使用PHP语法，获取当前时间戳
  php_file=`whereis php | awk {'print $2'}`
  timestamp=`${php_file} -r "echo time();"`
  # 使用随机文件夹名称，重新初始化变量
  name=opencart_${timestamp}

  # 安装可能需要的依赖
  yum install net-tools -y &>/dev/null

  # 判断端口是否被占用
  netstat -ant | grep ${port} &>/dev/null
  if [[ "$?" -eq 0 ]];then
    action "${port} 端口号已被占用" /bin/false
    exit 1
  else
    action "${port} 此端口号可以使用" /bin/true
  fi

  # 检查IP合法性
  if [[ $IP =~ ^([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.([0-9]{1,2}|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$ ]]
  then
    action "${IP} IP合法"
  else
    action "${IP} IP不合法" /bin/false
    exit 1
  fi

  # 判断数据库连接是否成功
  mysql_file=`whereis mysql | awk '{print $2}'`
  ${mysql_file} -uroot -p${passwd} -b --connect-expired-password <<EOF
CREATE DATABASE ${name};
EOF
  if [[ "$?" -eq 0 ]];then
    action "MySQL数据库连接成功，新建数据库名称为：${name}" /bin/true
  else
    action "MySQL数据库连接失败！" /bin/false
    exit 1
  fi
}

# 创建放置下载文件夹的目录，存在则提示，不存在则新建
createDir() {
  if [[ ! -e $dir ]]
    then
      mkdir $dir
  else
    echo "文件下载目录已存在！"
  fi
}

# 1.检查系统是否安装了，lnmp服务
checkLnmp() {
  # 1.打印系统版本
  cat /etc/centos-release
  # 2.检查nginx
  # 获取nginx的安装路径
  nginx_path=`whereis nginx| awk '{print $2}'`
  if [[ -d ${nginx_path} ]];then
    # 使用nginx -t检测是否nginx已安装
    ${nginx_path}/sbin/nginx -v
  else
    action "nginx 文件目录不存在" /bin/false
    exit 1
  fi
  # 3.检查mysql
  # 获取运行mysql文件
  mysql_file=`whereis mysql | awk {'print $2'}`
  if [[ -f ${mysql_file} ]];then
    ${mysql_file} -V
  else
    action "mysql 运行文件不存在" /bin/false
    exit 1
  fi
  # 4.检查PHP
  php_file=`whereis php | awk {'print $2'}`
  if [[ -f ${php_file} ]];then
    ${php_file} -r 'echo version_compare(phpversion(), "5.4.0", "<") == false;' &>/dev/null
    if [[ "$?" -eq 0 ]];then
      ${php_file} -v
    else
      action "php 版本号小于5.4.0" /bin/false
      exit 1
    fi
  else
    action "php 运行文件不存在" /bin/false
    exit 1
  fi
}

# 2.下载opencart3.0.3.2压缩包，并检查是否已存在，存在则不下载
# https://github.com/opencart/opencart/releases/download/3.0.3.2/opencart-3.0.3.2.zip
downloadOpencart() {
  # 检测文件（包括目录）是否存在，如果是，则返回 true。
  [[ -e $dir ]] && cd $dir
  if [ -f "opencart-3.0.3.2.zip" ];then
    # 解压缩文件
    decompressionOpencart "opencart-3.0.3.2.zip"
  else
    echo "正在下载 opencart-3.0.3.2.zip ，时间会有点久，请稍等..."
    # 不存在则下载压缩包
    wget https://github.com/opencart/opencart/releases/download/3.0.3.2/opencart-3.0.3.2.zip
    if [[ "$?" -eq 0 ]];then
      action "下载 opencart-3.0.3.2.zip 已完成" /bin/true
      # 解压缩文件
      decompressionOpencart "opencart-3.0.3.2.zip"
    else
      # 如果下载失败，就将这个文件删除
      rm -rf opencart-3.0.3.2.zip
      action "下载 opencart-3.0.3.2.zip 失败" /bin/false
      exit 1
    fi
  fi
}

# 3.解压缩，并将文件迁移至指定目录下
decompressionOpencart() {
  fileName=$1
  echo "开始解压缩 ${fileName} ..."
  # 安装解压与压缩依赖
  yum install -y zip unzip &>/dev/null
  unzip ${fileName} -d ${dir}/mydatabak &>/dev/null
  if [[ "$?" -eq 0 ]];then
    action "解压成功" /bin/true
  else
    action "解压失败！！！！" /bin/false
    exit 1
  fi
  # # 使用PHP语法，获取当前时间戳
  # php_file=`whereis php | awk {'print $2'}`
  # timestamp=`${php_file} -r "echo time();"`
  # # 使用随机文件夹名称
  # name=opencart_${timestamp}
  webSite=/var/www/${name}
  mkdir -p ${webSite}
  mv mydatabak/upload/* ${webSite}
  # 删除解压过的文件目录
  rm -rf ${dir}/mydatabak
  # 重新为全局变量赋值
  echo "网站根目录为：${webSite}"
}

# 创建一个apache用户和组，因为在opencart3中，所有的上传的东西，都是基于apache用户与组的，
# 若不创建这个用户与组，会造成无法上传扩展后报没有权限的错误
checkUser2Group() {
  # 检查apache用户与组是否存在
  cut -d : -f 1 /etc/group | grep apache &>/dev/null
  if [[ "$?" -ne 0 ]];then
    groupadd apache &>/dev/null
  fi
  cut -d : -f 1 /etc/passwd | grep apache &>/dev/null
  if [[ "$?" -ne 0 ]];then
    useradd -g apache apache &>/dev/null
  fi
}

# 4.修改opencart中文件权限和文件命名
empowermentFile() {
  checkUser2Group
  # 进入 webSite 网站根目录
  [[ -e ${webSite} ]] && cd ${webSite}
  # 将此网站的目录用户权限，全部配置给apache
  chown -R apache:apache ${webSite}
  # 文件重命名
  mv admin/config-dist.php admin/config.php
  mv config-dist.php config.php
  # 设置文件操作权限
  chmod 777 -R admin/config.php
  chmod 777 -R config.php
  chmod 777 image
  chmod 777 -R image/cache
  chmod 777 -R image/catalog
  chmod 777 -R system/storage/*
}

# 5.配置允许外网访问的ip及端口（配置nginx配置文件）
configNginx() {
  # 获取nginx 路径
  nginx_path=`whereis nginx| awk '{print $2}'`
  # 获取根目录名称，并将之当成conf的文件名
  # name=`echo ${webSite} | awk -F/ '{print $4}'`
  # 到这里，本人是在auto_lnmp.sh这个脚本中设置了，加载进nginx总配置文件的一个专门存储配置文件的目录
  touch ${nginx_path}/myConf/${name}.conf &>/dev/null
  # 为新建文件赋权
  chmod 755 ${nginx_path}/myConf/${name}.conf
# nginx 配置
(
cat <<EOF
server {
  listen       ${port};
  server_name  ${IP};
  root         ${webSite};
  index index.php index.html index.htm;
  # Load configuration files for the default server block.
  include /etc/nginx/default.d/*.conf;
  # client_max_body_size 50m;
  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }
  error_page 404 /404.html;
  location = /40x.html {
  }
  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
  }
  location ~ .php$ {
    try_files \$uri =404;
    fastcgi_pass 127.0.0.1:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi.conf;
  }
}
EOF
) > ${nginx_path}/myConf/${name}.conf
  # 重启nginx服务
  ${nginx_path}/sbin/nginx -s reload
}

# 6.检测防火墙是否开启，如果开启状态则需要开放对应的端口
checkFirewalld() {
  # 获取 firewalld 的状态，running表示运行
  status=`firewall-cmd --state`
  if [ ${status} -eq "running" ];then
    # 开放对应端口，允许外部访问，若是 阿里云 则不需要此层设置，需要直接去 阿里云 网站做相关配置
    if [[ `firewall-cmd --zone=public --add-port=${port}/tcp --permanent` -ne "success" ]];then
      action "${port} 端口设置失败" /bin/false
      exit 1
    fi
    if [[ `firewall-cmd --reload` -ne "success" ]];then
      action "firewall 服务重启失败" /bin/false
      exit 1
    fi
  fi
  # 开放端口 firewall-cmd --zone=public --add-port=80/tcp --permanent
  # 重启防火墙 firewall-cmd --reload
  # 查看开放的所有端口 firewall-cmd --list-ports
  # firewall-cmd --zone=public --remove-port=80/tcp --permanent  # 删除
}

# 7.删除opencart安装包（install）
removePackage() {
  webSite=/var/www/${name}
  if [[ -d ${webSite} ]];then
    rm -rf /var/www/${name}/install
    if [[ "$?" -ne 0 ]];then
      action "修复失败" /bin/false
      exit 1
    else
      [[ -e ${webSite} ]] && cd ${webSite}
      # 查找需要替换的那一行数据
      pf=`sed -n "/define('DIR_STORAGE',/p" ${webSite}/config.php`
      # 将之替换成新的数据
      sed -i "s#${pf}#define('DIR_STORAGE', '${webSite}/storage/');#g" ${webSite}/config.php
      sed -i "s#${pf}#define('DIR_STORAGE', '${webSite}/storage/');#g" ${webSite}/admin/config.php
      mv ${webSite}/system/storage/ ${webSite}/storage/
      if [[ "$?" -eq 0 ]];then
        action "修复成功" /bin/true
      else
        action "修复失败" /bin/false
      fi
    fi
  else
    action "你所输入的网站目录并不存在" /bin/false
  fi
  exit 1
}

removeOpencart3() {
  [[ -e $dir ]] && cd $dir
  # 删除已下载不完全的opencart3的压缩包
  rm -rf ${dir}/opencart*
  if [[ "$?" -eq 0 ]];then
    action "修复成功" /bin/true
  else
    action "修复失败" /bin/false
  fi
  exit 1
}

main() {
  checkIP2Port
  
  createDir
  checkLnmp
  sleep 2
  downloadOpencart
  sleep 2
  empowermentFile
  sleep 2
  configNginx
  sleep 2
  # checkFirewalld
}

if [[ "$NUM" -eq 1 ]];then
  read -p "请输入IP：" IP
  read -p "请输入端口号（port）：" port
  read -p "请输入Mysql数据库root权限的密码（password）：" passwd
  main
elif [[ "$NUM" -eq 2 ]];then
  read -p "请网站名称（以opencart_开头）：" name
  removePackage
elif [[ "$NUM" -eq 3 ]];then
  # 删除已下载不完全的opencart3就可以解决问题
  removeOpencart3
else
  action "选择的指令不在选项内，无法操作" /bin/false
  exit 1
fi
