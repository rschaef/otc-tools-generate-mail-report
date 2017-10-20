#!/bin/bash

#############################################################################
#
# generates e-mail for daily reports (OTC)
# use in /etc/crontab
# 03 0	* * *   user	if [[ -x ~/otc-tools/otc-daily-mail-report.sh ]]; then ~/otc-tools/otc-daily-mail-report.sh; fi 2>&1
#
#############################################################################

command -v `locate otc.sh` >/dev/null 2>&1 || {
		### 'otc-tools' downloaded?
        echo >&2 -e "\n["$0"] ToDo: git clone https://github.com/OpenTelekomCloud/otc-tools.git . Aborting.\n";
        exit 1;
}
command -v swaks >/dev/null 2>&1 || {
		### 'swaks' [Swiss Army Knife SMTP] installed?
        echo >&2 -e "\n["$0"] ToDo: apt-get install swaks . Aborting.\n";
        exit 1;
}

DEBUG=false;

OTC_SHELL=`locate otc.sh` ;
SWAKS=`which swaks`;

### read .ostackrc [ analog otc-tools ] #####################################
# $OS_USERNAME, $OS_USER_DOMAIN_NAME
# extended: $OS_SMTP, $OS_MAIL_FROM, $ OS_MAIL_TO
if [ -r ~/.ostackrc ];
then
	source ~/.ostackrc
else
	echo >&2 -e "\n["$0"] config: ~./ostackrc not found/readable . Aborting.\n";
	exit 1;	
fi

### variables ###############################################################
OTCUSER=$OS_USERNAME ;
OTCDOM=$OS_USER_DOMAIN_NAME ;
TO=$OS_MAIL_TO ;
FROM=$OS_MAIL_FROM ;
SMTP=$OS_SMTP ;

# array fuer die rueckgaben?
# 302	Found (Moved Temporarily) => OK
# ...
SUBJECT="OTC Report" ;
HEAD="" ;
BODY="" ;
NOACTION="nothing happend";
VMS=$($OTC_SHELL ecs list | wc -l) ;

# date from yesterday 00:00:00 - 23:59:59
# yesterday
DATE=$(date -d @$(($(date +%s)-86400)) +"%Y-%m-%d") ;
# yesterday 00:00:00 to unixtimestamp
DATEFROM=$(date --date "$DATE 00:00:00 +0200" +"%Y-%m-%d %H:%M:%S");
DATEFROM=$(date --date "$DATEFROM" +%s) ;
# yesterday 23:59:59 to unixtimestamp
DATETO=$(date --date "$DATE 23:59:59 +0200" +"%Y-%m-%d %H:%M:%S");
DATETO=$(date --date "$DATETO" +%s) ;




### html head ###############################################################
function createHTMLhead {
	HEAD+="
	<!DOCTYPE html>
	<html>
	<head>
		<meta http-equiv='Content-Type' content='text/html; charset=utf-8'>
		<meta http-equiv='Expires' content='0'>
		<meta http-equiv='Pragma' content='no-store'>
		<meta http-equiv='Cache-control' content='no-store'>
		<meta http-equiv='Cache' content='no-store'>
		<title>Daily OTC Report</title>
		<style>
			body { background-color: white; font-family: 'arial';}			
			h1 { color: #E20074; font-size: 1.4em; }
			th { color: white; background: #E20074; font-size: 1.2em; }
			th, td { text-align:left; padding-left: 1em; padding-right: 1em; }
			#reporthead { background-color: white; font-size: 1.2em; color: #E20074; width: 920px; }
			#reporttbl { padding-left: 0.5em; width: 920px; font-size: 1.0em; border: 1px; border-color: lightgrey; border-style: none none solid none; }
			#reportfoot { padding-left: 0.5em; width: 920px; }
		</style>
	</head>
	<body>
	<div style='margin: 1em 0 1em 0;'> 
	<h1>OTC Report</h1>
	<table id='reporthead'>
		<tr>
			<td>Domain</td>
			<td>$OTCDOM</td>
		</tr>
		<tr>
			<td>VMs</td>
			<td>$VMS</td>
		</tr>
		<tr>
			<td>Date</td>
			<td>$DATE</td>
		</tr>
	</table>
	</div>
	" ;
}

function generateIAM {
	### table auth head
	IAMLIST=$($OTC_SHELL trace show IAM) ;
	BODY+="
	<table id='reporttbl'>
	<thead>
		<tr>
			<th>Date</th>
			<th>Action</th>
			<th>User</th>
			<th>SourceIP</th>
			<th>Status</th>
		</tr>
		<tr>
			<td colspan="5">&nbsp;</td>
		</tr>
	</thead>
	" ;
	
	### table auth content
	BODY+="<tbody>" ;
	action=0 ;
	n=0; 
	while read -r LINE;
	do
		array=(${LINE//,/}) ;
		arraylength=${#array[@]} ;
		### get actions between $DATE 00:00:00 and 23:59:59
		if [[ 
			(( ${array[0]::-3} == $DATEFROM ) || ( ${array[0]::-3} > $DATEFROM )) 
			&& 
			(( ${array[0]::-3} == $DATETO ) || ( ${array[0]::-3} < $DATETO )) 
		]];
		then
			action=$(($action+1)) ;
			### set background for even line 
			modulo=$((n%2)) ;
			if [[ $modulo == 0 ]];
			then
				BODY+="<tr style='background:lightgrey;'>" ;
			else
				BODY+="<tr>" ;
			fi
			for (( i=0; i<${arraylength}; i++ ));
			do
		
				if [ $i == 0 ];
				then
					date=${array[0]::-3}
					date=$(date -d @"$date" +"%Y-%m-%d %H:%M:%S %z") ;
					BODY+="<td>$date</td>" ;
				else
					if [[ $arraylength == 6 ]] && [[ $i == 2 ]];
					then
						# concat array[3]#array[2] => OTCdomain#User
						BODY+="<td>${array[$i+1]}#${array[$i]}</td>" ;
						i=$(($i+1)) ;    	
					else
						BODY+="<td>${array[$i]}</td>" ;
					fi
				fi
			done
			BODY+="</tr>" ;
			n=$(($n+1)) ;
		fi
	done <<< "$IAMLIST"
	if [[ $action == 0 ]];
	then
		BODY+="<tr><td colspan=5><font color='#E20074'><b>IAM: $NOACTION</b></font></td></tr>" ;				
	fi	
	BODY+="</tbody></table><br /><br />" ;
}

function generateECS {
	### table ecs head
	ECSLIST=$($OTC_SHELL trace show ECS) ;
	BODY+="
	<table id='reporttbl'>
	<thead>
		<tr>
			<th>Date</th>
			<th>Action</th>
			<th>ECS</th>
			<th>User</th>
			<th>SourceIP</th>
			<th>Status</th>
		</tr>
		<tr>
			<td colspan="5">&nbsp;</td>
		</tr>
	</thead>
	" ;
	
	### table auth content
	BODY+="<tbody>" ;
	action=0 ;
	n=0; 
	while read -r LINE;
	do
		array=(${LINE//,/}) ;
		arraylength=${#array[@]} ;
		if [[ 
			(( ${array[0]::-3} == $DATEFROM ) || ( ${array[0]::-3} > $DATEFROM )) 
			&& 
			(( ${array[0]::-3} == $DATETO ) || ( ${array[0]::-3} < $DATETO )) 
		]];
		then
			action=$(($action+1)) ;
			modulo=$((n%2)) ;
			if [[ $modulo == 0 ]];
			then
				BODY+="<tr style='background:lightgrey;'>" ;
			else
				BODY+="<tr>" ;
			fi
			for (( i=0; i<${arraylength}; i++ ));
			do	
				if [ $i == 0 ];
				then
					date=${array[0]::-3}
					date=$(date -d @"$date" +"%Y-%m-%d %H:%M:%S %z") ;
					BODY+="<td>$date</td>" ;
				else
					BODY+="<td>${array[$i]}</td>" ;
				fi
			done
			BODY+="</tr>" ;
			n=$(($n+1)) ;
		fi
	done <<< "$ECSLIST"
	if [[ $action == 0 ]];
	then
		BODY+="<tr><td colspan=5><font color='#E20074'><b>ECS: $NOACTION</b></font></td></tr>" ;				
	fi		
	BODY+="</tbody></table><br /><br />" ;
}

function generateCTS {
	### table cts head
	CTSLIST=$($OTC_SHELL trace show CTS) ;
	BODY+="
	<table id='reporttbl'>
	<thead>
		<tr>
			<th>Date</th>
			<th>Action</th>
			<th>CTS</th>
			<th>User</th>
			<th>SourceIP</th>
		</tr>
		<tr>
			<td colspan="5">&nbsp;</td>
		</tr>
	</thead>
	" ;
	
	### table auth content
	BODY+="<tbody>" ;
	action=0 ;	
	n=0 ; 
	while read -r LINE;
	do
		array=(${LINE//,/}) ;
		arraylength=${#array[@]} ;
		if [[ 
			(( ${array[0]::-3} == $DATEFROM ) || ( ${array[0]::-3} > $DATEFROM )) 
			&& 
			(( ${array[0]::-3} == $DATETO ) || ( ${array[0]::-3} < $DATETO )) 
		]];
		then
			action=$(($action+1)) ;
			modulo=$((n%2)) ;
			if [[ $modulo == 0 ]];
			then
				BODY+="<tr style='background:lightgrey;'>" ;
			else
				BODY+="<tr>" ;
			fi
			for (( i=0; i<${arraylength}; i++ ));
			do
				if [ $i == 0 ];
				then
					date=${array[0]::-3}
					date=$(date -d @"$date" +"%Y-%m-%d %H:%M:%S %z") ;
					BODY+="<td>$date</td>" ;
				else
					BODY+="<td>${array[$i]}</td>" ;
				fi
			done
			BODY+="</tr>" ;
			n=$(($n+1)) ;
		fi
	done <<< "$CTSLIST"
	if [[ $action == 0 ]];
	then
		BODY+="<tr><td colspan=5><font color='#E20074'><b>CTS: $NOACTION on $DATE</b></font></td></tr>" ;				
	fi		
	BODY+="</tbody></table><br /><br />" ;
}

function generateUSERS {
	### table cts head
	USERLIST=$($OTC_SHELL iam users) ;
	BODY+="
	<table id='reporttbl'>
	<thead>
		<tr>
			<th>User</th>
			<th>Active</th>
			<th>Full Name</th>
		</tr>
		<tr>
			<td colspan="3">&nbsp;</td>
		</tr>
	</thead>
	" ;

	### table auth content
	BODY+="<tbody>" ;
	n=0 ; 
	while read -r LINE;
	do
		array=(${LINE//,/}) ;
		arraylength=${#array[@]} ;
		#($DEBUG) && echo -e "ArrayLength: ${arraylength}\n" ;
		modulo=$((n%2)) ;
		if [[ ${arraylength} == 6 ]];
		then
			if [[ $modulo == 0 ]];
			then
				BODY+="<tr style='background:lightgrey;'>" ;
			else
				BODY+="<tr>" ;
			fi			
			for (( i=1; i<(${arraylength}-2); i++ ));
			do
				#($DEBUG) && echo -e "${array[$i]}" ;
				if [[ $i == 3 ]];
				then
					BODY+="<td>${array[$i]} ${array[$i+1]}</td>" ;
				else
					BODY+="<td>${array[$i]}</td>" ;
				fi
			done
			BODY+="</tr>"
			n=$(($n+1)) ;
		fi
	done <<< "$USERLIST"
	BODY+="</tbody></table><br /><br />" ;

}
### table footer ############################################################
function createHTMLfoot {
	#DATE=$(date +"%Y-%m-%d %H:%M:%S %:z") ;
	#DATE=$(date +"%Y-%m-%d %H:%M:%S %Z") ;
	BODY+="
	<table id='reportfoot'>
	<tr><td colspan='5'>&nbsp;</td></tr>
	<tr><td colspan=5 style='font-size:0.6em;text-align:right;'>Generated on $(date +"%Y-%m-%d %H:%M:%S %Z") by T-Systems MMS @$OTCUSER</td></tr>
	</table>
	</body>
	</html>
	" ;
}

### send mail ###############################################################
function sendMail {
	MAILBODY=$(echo $HEAD$BODY | base64 ) ;
	$SWAKS 	--from $FROM \
			--to $TO \
			--header "Subject: $SUBJECT $OTCDOM $DATE" \
			--header "X-Mailer: OTC swaks" \
			--add-header "MIME-Version: 1.0" \
			--add-header "Content-Type: text/html; charset=UTF-8" \
			--add-header "Content-transfer-encoding: base64" \
			--body "$MAILBODY" \
			--protocol ESMTP \
			--server $SMTP \
			--tls-optional \
			--silent 1
}	

### call functions ##########################################################
# keep order:
createHTMLhead ;
generateIAM ;
generateECS ;
generateCTS ;
generateUSERS ;
createHTMLfoot ;
if ($DEBUG)
then 
	echo "$HEAD$BODY" ;
else
	sendMail ;
fi

exit 0