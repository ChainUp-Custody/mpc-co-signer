#!/bin/bash

# Colors and Symbols
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
CHECK_MARK="${GREEN}✔${NC}"
WARN_MARK="${YELLOW}⚠️${NC}"
CROSS_MARK="${RED}✘${NC}"

WORK_DIR=$(
              cd $(dirname $0)
              pwd
          )
echo "work dir: ${WORK_DIR}"

# Check and download co-signer binary
echo ""
echo "Select installation type:"
echo "1) Standard (Default)"
echo "2) SGX (Intel Software Guard Extensions)"
echo -n "Enter choice [1]: "
read INSTALL_TYPE

echo ""
echo -e "${WARN_MARK}  install.sh will clean startup.sh, stop.sh, conf/config.yaml, conf/keystore.json."
echo -n "Continue? [Y/N(default)]: "
read CLEAN_CONF
case $CLEAN_CONF in
(Y | y)
  CONF_DIR="${WORK_DIR}/conf"
  mkdir -p $CONF_DIR
  > ./conf/config.yaml
  > ./startup.sh
  > ./stop.sh
  echo {} > ./conf/keystore.json

  if [ "$INSTALL_TYPE" = "2" ]; then
    echo -e "${GREEN}Selected SGX installation.${NC}"
    
    # Check for ego
    if ! command -v ego >/dev/null 2>&1; then
      echo "ego not found. Installing ego..."
      # Install dependencies
      if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update
          sudo apt-get install -y build-essential libssl-dev wget
      fi
      
      # Download and install ego
      # Fetch latest ego version
      EGO_LATEST_TAG=$(curl -s https://api.github.com/repos/edgelesssys/ego/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
      EGO_VERSION=${EGO_LATEST_TAG#v}
      EGO_DEB="ego_${EGO_VERSION}_amd64_ubuntu-22.04.deb"
      
      wget "https://github.com/edgelesssys/ego/releases/download/${EGO_LATEST_TAG}/${EGO_DEB}"
      sudo apt-get install -y "./${EGO_DEB}"
      rm -f "${EGO_DEB}"
      
      if ! command -v ego >/dev/null 2>&1; then
          echo -e "${CROSS_MARK} Failed to install ego. Please install it manually."
          exit 1
      fi
      echo -e "${CHECK_MARK} ego installed successfully."
    else
      echo -e "${CHECK_MARK} ego is already installed."
    fi
  fi

  if [ ! -f "${WORK_DIR}/co-signer" ]; then
    echo ""
    echo -e "${WARN_MARK} co-signer binary not found in ${WORK_DIR}."
    echo "Attempting to download the latest version from GitHub..."

    # Fetch latest tag
    LATEST_TAG=$(curl -s https://api.github.com/repos/ChainUp-Custody/mpc-co-signer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [ -z "$LATEST_TAG" ]; then
      echo -e "${CROSS_MARK} Failed to fetch latest version info from GitHub."
      exit 1
    fi
    
    echo "Latest version: ${LATEST_TAG}"
    
    if [ "$INSTALL_TYPE" = "2" ]; then
      # SGX version uses non-static binary
      DOWNLOAD_URL="https://github.com/ChainUp-Custody/mpc-co-signer/releases/download/${LATEST_TAG}/co-signer-linux-${LATEST_TAG}"
    else
      # Standard version uses static binary
      DOWNLOAD_URL="https://github.com/ChainUp-Custody/mpc-co-signer/releases/download/${LATEST_TAG}/co-signer-linux-${LATEST_TAG}-static"
    fi
    
    echo "Downloading from: ${DOWNLOAD_URL}"
    curl -L -f -o "${WORK_DIR}/co-signer" "${DOWNLOAD_URL}"
    
    if [ $? -eq 0 ]; then
      chmod +x "${WORK_DIR}/co-signer"
      echo -e "${CHECK_MARK} Download success."
    else
      echo -e "${CROSS_MARK} Download failed. Please check your network or manually download the binary."
      rm -f "${WORK_DIR}/co-signer"
      exit 1
    fi
  fi
  ;;
(*)
  echo "Exit!!!"
  exit 0
  ;;
esac

echo ""
APP_ID=""
echo -e "App id can be found in https://custody.chainup.com/mpc/center/api."
echo -n "Please enter app id: "
read APP_ID

echo ""
echo -n "Please input custom withdraw transaction callback url (skip by enter): "
read WITHDRAW_CALLBACK_URL

echo ""
echo -n "Please input custom web3 transaction callback url (skip by enter): "
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
#!/bin/bash

project_path=\$(
    cd \$(dirname \$0)
    pwd
)

STR_PASSWORD=""
echo -n "Please enter your password (16 characters): "
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

STOP_TMPL=$(cat << 'STOP_EOF'
#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Find PID of co-signer server
# We search for "co-signer -server" to avoid killing other instances or the script itself
PID=$(ps -ef | grep "co-signer -server" | grep -v grep | awk '{print $2}')

if [ -z "$PID" ]; then
    echo -e "${YELLOW}co-signer is not running.${NC}"
    exit 0
fi

echo -e "Stopping co-signer (PID: ${GREEN}$PID${NC})..."
kill $PID

# Wait for process to exit
for i in {1..5}; do
    if ! ps -p $PID > /dev/null; then
        echo -e "${GREEN}co-signer stopped successfully.${NC}"
        exit 0
    fi
    sleep 1
done

# Force kill if still running after timeout
if ps -p $PID > /dev/null; then
    echo -e "${YELLOW}co-signer did not stop gracefully. Force killing...${NC}"
    kill -9 $PID
    echo -e "${GREEN}co-signer stopped.${NC}"
fi
STOP_EOF
)

PASSWORD=""
echo ""
echo -n "Please enter your password (16 characters): "
stty -echo
read PASSWORD
stty echo
echo ""

# Function to perform SGX signing and bundling
sign_and_bundle_sgx() {
    # Check if already bundled
    if ./co-signer -v 2>&1 | grep -i "loading enclave" >/dev/null; then
         echo -e "${CHECK_MARK} co-signer is already SGX bundled. Skipping signing/bundling."
         return 0
    fi

    echo ""
    echo "Signing binary for SGX..."
    
    # Calculate heap size (92% of available memory in MB)
    AVAILABLE_MEM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    HEAP_SIZE_MB=$(echo "$AVAILABLE_MEM_KB * 0.92 / 1024" | bc | awk '{print int($1)}')
    
    echo "Available Memory: $((AVAILABLE_MEM_KB/1024)) MB, Configured Heap Size: ${HEAP_SIZE_MB} MB"

    # Create enclave.json
    cat > ./enclave.json << EOF
{
    "exe": "co-signer",
    "key": "private.pem",
    "debug": false,
    "heapSize": ${HEAP_SIZE_MB},
    "executableHeap": false,
    "productID": 1,
    "securityVersion": 1,
    "mounts": [
        {"readOnly": false, "type": "hostfs", "source": "/etc/ssl/certs/", "target": "/etc/ssl/certs/"},
        {"readOnly": false, "type": "hostfs", "source": "${WORK_DIR}", "target": "${WORK_DIR}"}
    ],
    "env": [
        {"name": "HOME", "fromHost": true},
        {"name": "PWD", "value": "${WORK_DIR}"}
    ],
    "files": null
}
EOF

    # Sign the binary
    ego sign co-signer
    
    # Bundle the binary
    ego bundle co-signer co-signer.sgx
    
    if [ $? -eq 0 ]; then
        # Replace original binary with bundled one
        mv co-signer.sgx co-signer
        chmod +x co-signer
        echo -e "${CHECK_MARK} SGX signing and bundling success."
        return 0
    else
        echo -e "${CROSS_MARK} SGX signing/bundling failed."
        return 1
    fi
}

# Check if binary runs (for SGX non-static binary)
SGX_BUNDLED_EARLY=false
if [ "$INSTALL_TYPE" = "2" ]; then
    echo "Checking if non-static binary runs..."
    ./co-signer -v > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${WARN_MARK} Non-static binary failed to run. Attempting to build SGX bundle first..."
        sign_and_bundle_sgx
        if [ $? -ne 0 ]; then
            exit 1
        fi
        SGX_BUNDLED_EARLY=true
    else
        echo -e "${CHECK_MARK} Non-static binary runs correctly."
    fi
fi

RESULT=$(echo ${PASSWORD} | ./co-signer -rsa-gen)
STATUS=$?
if [ "$STATUS" != 0 ];then
  echo -e "${CROSS_MARK} RSA key pair creation failed!"
  echo "$RESULT"
  exit $STATUS
fi
echo -e "${CHECK_MARK} RSA key pair create success. You can find RSA public key in conf/keystore.json"

echo ""
echo "ChainUp RSA public key can be found in https://custody.chainup.com/mpc/center/api"
echo -n "Please input ChainUp RSA public key: "
read CHAINUP_PUBLIC_KEY
RESULT=$(echo ${PASSWORD} | ./co-signer -custody-pub-import ${CHAINUP_PUBLIC_KEY})
STATUS=$?
if [ "$STATUS" != 0 ];then
  echo -e "${CROSS_MARK} Import custody public key failed!"
  echo "$RESULT"
  exit $STATUS
fi
echo -e "${CHECK_MARK} Import custody public key success."

echo ""
echo "Custom RSA public key(not Client system RSA public key), used for verifying withdraw data. https://custodydocs-en.chainup.com/api-references/mpc-apis/co-signer/flow#automatic-signature-signature-sign-verification-method"
echo -n "Please input Custom RSA public key for verify withdraw data: "
read CUSTOM_PUBLIC_KEY
if [ "$CUSTOM_PUBLIC_KEY" != "" ];then
  RESULT=$(echo ${PASSWORD} | ./co-signer -verify-sign-pub-import ${CUSTOM_PUBLIC_KEY})
  STATUS=$?
  if [ "$STATUS" != 0 ];then
    echo -e "${CROSS_MARK} Import verify sign public key failed!"
    echo "$RESULT"
    exit $STATUS
  fi
  echo -e "${CHECK_MARK} Import verify sign public key success."
fi

if [ ! -d "conf" ]; then
  mkdir -p conf
fi

cat>./conf/config.yaml<< EOF
${CONF_TMPL}
EOF

echo ""
echo "Verifying configuration..."
RESULT=$(echo ${PASSWORD} | ./co-signer -check-conf)
echo "$RESULT"

## reset password
PASSWORD=""

# SGX Signing Process (if not done early)
if [ "$INSTALL_TYPE" = "2" ] && [ "$SGX_BUNDLED_EARLY" = "false" ]; then
    sign_and_bundle_sgx
    if [ $? -ne 0 ]; then
        exit 1
    fi
fi

cat>./startup.sh<< EOF
${STARTUP_TMPL}
EOF

cat>./stop.sh<< EOF
${STOP_TMPL}
EOF

chmod u+x ./startup.sh
chmod u+x ./stop.sh
echo ""
echo -e "${CHECK_MARK} Install success!!!!!"
echo -e "Please start co-signer with ${GREEN}./startup.sh${NC}"
