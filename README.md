# PSAI
Collection of powershell scripts and or snippets for collecting information about windows systems

# USB Hunter
Script will take input of targets from various choices:
Local system
LDAP Query
Comma separated list
And then query the targets via Win32.Registry* and advapi32 to get information on what USB storage devices has been attached to the system.
### Dependencies
- Powershell 2.0 and above
- TCP 445 against targets
- Sufficient permissions to extract information from HKLM on targets

### Features coming
- Correlation with setupapi log for more information
