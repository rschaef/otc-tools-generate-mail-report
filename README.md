# otc-tools-generate-mail-report
generates e-mail for daily reports (OpenTelekomCloud otc-tools)
for use in /etc/crontab e.g.

03 0	* * *   user	if [[ -x ~/otc-tools/otc-daily-mail-report.sh ]]; then ~/otc-tools/otc-daily-mail-report.sh; fi 2>&1
