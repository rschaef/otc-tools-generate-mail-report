#!/bin/bash

OTCSH=`locate otc.sh`;

for ECS in `${OTCSH} ecs list | awk -F' ' '{print $1}'`;
do
        ${OTCSH} ecs start-instances $ECS;
done

exit 0
