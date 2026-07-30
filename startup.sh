#!/bin/bash  
project_path=$(
    cd $(dirname $0)
    pwd
)

STR_PASSWORD=""
echo -n "Please enter your password:"
stty -echo
read STR_PASSWORD
stty echo


if [ ! -n "$STR_PASSWORD" ]; then
    echo "Password cannot be null"
    exit 1
fi

echo ""
echo "Startup Program..."
echo ""

# start
echo ${STR_PASSWORD} | nohup ${project_path}/co-signer -server >>nohup.out 2>&1 &
