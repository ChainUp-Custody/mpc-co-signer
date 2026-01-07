#!/bin/bash

WORK_DIR=$(
              cd $(dirname $0)
              pwd
          )
echo "work dir: ${WORK_DIR}"
scriptFile=$0

if [[ $1 == '' ]];then

wget -c "https://github.com/ChainUp-Custody/mpc-co-signer/releases/download/v1.2.4/co-signer-linux-v1.2.4" -O co-signer
chmod a+x co-signer

DOCKER_FILE=$(cat <<- EOF
FROM --platform=linux/amd64 ubuntu:22.04

WORKDIR /co-signer
VOLUME ${WORK_DIR}

# 配置Ubuntu镜像源（使用清华大学镜像源，对x86-64支持更好）
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list && \
    sed -i 's@//.*security.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list

# 清理并更新包列表
RUN apt-get clean && apt-get update

# 安装sudo
RUN apt-get install -y sudo

# 重新更新包列表
RUN sudo apt-get clean && sudo apt-get update

# 配置时区
RUN DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get -y install tzdata

# 分步安装基础包，提高成功率
RUN sudo apt-get install -y --no-install-recommends vim git curl python3 || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing vim git curl python3)
RUN sudo apt-get install -y --no-install-recommends net-tools cron wget || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing net-tools cron wget)
# 安装编译工具
RUN sudo apt-get install -y --no-install-recommends gcc make autoconf automake autotools-dev m4 pkg-config || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing gcc make autoconf automake autotools-dev m4 pkg-config)

# 分步安装开发依赖包，提高成功率
RUN sudo apt-get install -y --no-install-recommends libtool || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing libtool)
RUN sudo apt-get install -y --no-install-recommends libzmq3-dev || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing libzmq3-dev)
RUN sudo apt-get install -y --no-install-recommends libminiupnpc-dev || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing libminiupnpc-dev)
RUN sudo apt-get install -y --no-install-recommends libssl-dev || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing libssl-dev)
RUN sudo apt-get install -y --no-install-recommends libevent-dev || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing libevent-dev)
RUN sudo apt-get install -y --no-install-recommends bsdmainutils build-essential || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing bsdmainutils build-essential)

# 修复依赖关系并安装boost库
RUN sudo apt-get install -f && sudo apt-get autoremove -y
RUN sudo apt-get install -y --no-install-recommends libboost-all-dev || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing libboost-all-dev)

# 最后安装软件源管理工具并清理
RUN sudo apt-get install -y --no-install-recommends software-properties-common || \
    (sudo apt-get update && sudo apt-get install -y --fix-missing software-properties-common)
RUN sudo apt-get clean && sudo apt-get update
RUN echo "cd /co-signer/ && /bin/bash ${scriptFile} docker" > /root/.cosigner_init
RUN echo "/bin/bash /root/.cosigner_init" >> /root/.bashrc

EOF
)

> ./Dockerfile
cat>Dockerfile<< EOF
${DOCKER_FILE}
EOF

docker stop co-signer
docker rm co-signer
docker image rm co-signer:1.0
docker image rm ubuntu:22.04
docker build --platform=linux/amd64 --no-cache -t co-signer:1.0 .
docker run --platform=linux/amd64 -d -it -v ${WORK_DIR}:/co-signer --name co-signer  co-signer:1.0
docker exec -it co-signer /bin/bash

exit 0
fi

echo ""
echo "install.sh will clean startup.sh、conf/config.yaml、conf/keystore.json, continue [Y/N(default)]?"
read CLEAN_CONF
case $CLEAN_CONF in
(Y | y)
  CONF_DIR="${WORK_DIR}/conf"
  mkdir -p $CONF_DIR
  > ./conf/config.yaml
  > ./startup.sh
  echo {} > ./conf/keystore.json
  ;;
(*)
  echo "exit!!!"
  exit 0
  ;;
esac

echo ""
APP_ID=""
echo "App id can find in https://custody.chainup.com/mpc/center/api."
echo "Please enter app id: (e.g. 6866b043a013680ea91be7e6fdcd2af4)"
read APP_ID

echo ""
echo "Please input custom withdraw transaction callback url(skip by enter):"
read WITHDRAW_CALLBACK_URL

echo ""
echo "Please input custom web3 transaction callback url(skip by enter):"
read WEB3_CALLBACK_URL

CONF_TMPL=$(cat <<- EOF
## Main Configuration Information
main:
    ## [Required] Co-signer service IP address
    tcp: "0.0.0.0:28888"
    ## [Required] Encrypted storage file used by v1.1.x version
    keystore_file: "conf/keystore.json"

## Custody System
custody_service:
    ## [Required] app_id, obtained after creating a merchant
    app_id: "${APP_ID}"
    ## [Required] api domain address, see interface documentation
    domain: "https://openapi.chainup.com/"
    ## [Optional] Request and response language, supporting zh_CN and en_US
    language: "en_US"

## Client System
custom_service:
    ## [Optional] Withdrawal callback client system address for signature confirmation before signing, details see: https://custodydocs-zh.chainup.com/api-references/mpc-apis/co-signer/callback/withdraw, mandatory sign verification when not configured
    withdraw_callback_url: "${WITHDRAW_CALLBACK_URL}"
    ## [Optional] Web3 transaction callback client system address for signature confirmation before signing, details see: https://custodydocs-zh.chainup.com/api-references/mpc-apis/co-signer/callback/web3, mandatory sign verification when not configured
    web3_callback_url: "${WEB3_CALLBACK_URL}"
EOF
)

STARTUP_TMPL=$(cat <<- EOF
#!/bin/bash  \

project_path=\$(
    cd \$(dirname \$0)
    pwd
)

STR_PASSWORD=""
echo -n "Please enter your password:"
stty -echo
read STR_PASSWORD
stty echo


if [ ! -n "\$STR_PASSWORD" ]; then
    echo "Password cannot be null"
    exit 1
fi

echo ""
echo "Startup Program..."
echo ""

# start
echo \${STR_PASSWORD} | nohup \${project_path}/co-signer -server >>nohup.out 2>&1 &

EOF
)

PASSWORD=""
echo ""
echo "Please enter your password:"
stty -echo
read PASSWORD
stty echo
RESULT=$(echo ${PASSWORD} | ./co-signer -rsa-gen)
echo $RESULT
STATUS=$?
if [ "$STATUS" != 0 ];then
  exit $STATUS
fi
echo "rsa key pair create success, you can find rsa public key in conf/keystore.json"

echo ""
echo "ChainUp RSA public key can find in https://custody.chainup.com/mpc/center/api"
echo "Please input ChinaUp RSA public key:"
read CHAINUP_PUBLIC_KEY
RESULT=$(echo ${PASSWORD} | ./co-signer -custody-pub-import ${CHAINUP_PUBLIC_KEY})
echo $RESULT
STATUS=$?
if [ "$STATUS" != 0 ];then
  exit $STATUS
fi

echo ""
echo "Custom RSA public key, use for verify withdraw data. https://custodydocs-en.chainup.com/api-references/mpc-apis/co-signer/flow#automatic-signature-signature-sign-verification-method"
echo "Please input Custom RSA public key for verify withdraw data:"
read CUSTOM_PUBLIC_KEY
if [ "CUSTOM_PUBLIC_KEY" != "" ];then
  RESULT=$(echo ${PASSWORD} | ./co-signer -verify-sign-pub-import ${CUSTOM_PUBLIC_KEY})
  echo $RESULT
  STATUS=$?
  if [ "$STATUS" != 0 ];then
    exit $STATUS
  fi
fi

echo ${CONF_TMPL} > ./conf/config.yaml

cat>./conf/config.yaml<< EOF
${CONF_TMPL}
EOF

cat>./startup.sh<< EOF
${STARTUP_TMPL}
EOF

chmod u+x ./startup.sh
echo ""
echo "install success!!!!!"

echo "${PASSWORD}"| nohup ./co-signer -server &

echo "docker exec -it co-signer /bin/bash"

PASSWORD=""

> /root/.cosigner_init

tail nohup.out
