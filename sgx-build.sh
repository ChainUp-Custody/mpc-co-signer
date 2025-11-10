#!/bin/bash
## sgx build command
## run on ubuntu:20.04

#! /bin/bash
if command -v ego >/dev/null 2>&1; then
  echo "ego already installed..."
else
  apt update
  apt install -y sudo
  sudo apt update

  export DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC

  apt-get -y install tzdata
  sudo apt install -y vim git curl python3 net-tools cron wget
  sudo apt install -y gcc make autoconf automake autotools-dev m4 pkg-config
  sudo apt install -y libtool libboost-all-dev libzmq3-dev libminiupnpc-dev libssl-dev libevent-dev bsdmainutils build-essential
  sudo apt install -y bsdmainutils build-essential
  sudo apt-get install -y software-properties-common
  sudo apt-get update
  sudo wget -qO- https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key | sudo apt-key add
  sudo add-apt-repository "deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu `lsb_release -cs` main"
  sudo wget https://github.com/edgelesssys/ego/releases/download/v1.3.0/ego_1.3.0_amd64.deb
  sudo apt install -y ./ego_1.3.0_amd64.deb build-essential libssl-dev
fi

WORK_DIR=$(
              cd $(dirname $0)
              pwd
          )
echo "work dir: ${WORK_DIR}"
echo ""

CO_SIGNER_BIN=""
echo "Please input co-signer origin bin file name which download in https://github.com/ChainUp-Custody/mpc-co-signer/releases/:"
read CO_SIGNER_BIN

if [ ! -f "$CO_SIGNER_BIN" ]; then
    echo "$CO_SIGNER_BIN not exist"
    exit 1
fi

>./enclave.json
cat>./enclave.json<< EOF
 {
     "exe": "${CO_SIGNER_BIN}",
     "key": "private.pem",
     "debug": true,
     "heapSize": 61440,
     "executableHeap": false,
     "productID": 1,
     "securityVersion": 1,
     "mounts": [{"readOnly":false, "type":"hostfs", "source":"/etc/ssl/certs/", "target":"/etc/ssl/certs/"},{"readOnly":false, "type":"hostfs", "source":"${WORK_DIR}", "target":"${WORK_DIR}"}],
     "env": [{"name":"HOME","fromHost":true},{"name":"PWD","value":"${WORK_DIR}"}],
     "files": null
 }
EOF

today=$(date "+%Y%m%d%H%M%S")
CO_SIGNER_SGX_BIN="${CO_SIGNER_BIN}.${today}"

export OE_SIMULATION=1
ego sign ${CO_SIGNER_BIN}
ego bundle ${CO_SIGNER_BIN} $CO_SIGNER_SGX_BIN
chmod u+x $CO_SIGNER_SGX_BIN

## need disable simulation end build
unset OE_SIMULATION

echo "Build ${CO_SIGNER_SGX_BIN} success!!!!!"
echo "Please exec \`unset OE_SIMULATION\` disable simulation env"
