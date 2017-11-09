#!/bin/bash

command -v `locate otc.sh` >/dev/null 2>&1 || {
        echo >&2 -e "\n["$0"] ToDo: git clone https://github.com/OpenTelekomCloud/otc-tools.git . Aborting.\n";
        exit 1;
}

OTC_SHELL=`locate otc.sh` ;

for ECS in `${OTC_SHELL} ecs list | grep ACTIVE | awk -F' ' '{print $1}'`;
do
	echo -e "Stopping >> $ECS << now ..." ; 
	${OTC_SHELL} ecs stop-instances $ECS ;
done

exit 0