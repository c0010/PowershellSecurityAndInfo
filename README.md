# PSAI
Collection of powershell scripts and or snippets for collecting information about windows systems

# ===== PS DNS History
Script is meant to be run on a schedule to discover all the DNS records and create a history over records that change IP address or gets deleted.
Output modes are CSV or SQL.
If a record gets deleted only the hostname will get logged in the removal log (since it's removed it's complicated to determine what IP address it had :) ) 
Only integrated authentication to SQL database is used for the moment.
### Pre-reqs
Before running the script in output mode SQL create a database then run PSDNSCreateTable.sql and PSDNSCreateTableDeleted.sql
Make sure to edit all the properties in PSDNSHistory.config to the correct values.

### Dependencies
- Powershell 5.0 and above
- DnsServer module
- Read permissions on the zones targeted
- SQL Server Database with DBO on target database
- dbatools Powershell module https://dbatools.io/

### Coming later
- Improving performance


# ===== USB Hunter (DO NOT USE ATM)
Script will take input of targets from various choices:
Local system
LDAP Query
Comma separated list
And then query the targets via Win32.Registry* and advapi32 to get information on what USB storage devices has been attached to the system.
### Dependencies
- Powershell 2.0 and above
- TCP 445 against targets
- Sufficient permissions to extract information from HKLM on targets
### Coming later
- Correlation with setupapi log for more information