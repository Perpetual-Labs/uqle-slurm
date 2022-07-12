#!/usr/bin/env bash

echo "post-install script has $# arguments"
for arg in ${@}
do
    echo "arg: ${arg}"
done

echo ${@}
