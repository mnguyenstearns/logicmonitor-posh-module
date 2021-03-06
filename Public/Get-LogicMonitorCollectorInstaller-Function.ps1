﻿Function Get-LogicMonitorCollectorInstaller {
    <#
        .DESCRIPTION 
            Generates and downloads a 64-bit Windows, LogicMonitor Collector installer. If successful, return the download path.
        .NOTES
            Author: Mike Hashemi
            V1 date: 27 December 2016
            V1.0.0.1 date 15 January 2017
                - Added parameter sets for collector properties.
                - Added support for collector ID retrieval based on the hostname.
            V1.0.0.2 date 31 January 2017
                - Updated code to support the Get-LogicMonitorCollectors syntax for ID retrieval.
                - Updated error handling.
            V1.0.0.3 date: 31 January 2017
                - Updated error output color.
                - Streamlined header creation (slightly).
            V1.0.0.4 date: 31 January 2017
                - Added $logPath output to host.
            V1.0.0.5 date: 31 Janyary 2017
                - Added additional logging.
            V1.0.0.6 date: 10 February 2017
                - Updated procedure order.
                - Updated documentation.
            V1.0.0.7 date: 3 May 2017
                - Removed code from writing to file and added Event Log support.
                - Updated code for verbose logging.
                - Changed Add-EventLogSource failure behavior to just block logging (instead of quitting the function).
            V1.0.0.8 date: 14 May 2017
                - Fixed bug in output (incorrect index number).
                - Replaced ! with -NOT.
            V1.0.0.9 date: 23 April 2018
                - Updated code to allow PowerShell to use TLS 1.1 and 1.2.
            V1.0.0.10 date: 10 May 2018
                - Replaced Invoke-WebRequest with a System.Net.WebClient object.
                - Added support for synchronous and asynchronous downloads.
                - Added parameter type casting.
        .LINK
            
        .PARAMETER AccessId
            Mandatory parameter. Represents the access ID used to connected to LogicMonitor's REST API.    
        .PARAMETER AccessKey
            Mandatory parameter. Represents the access key used to connected to LogicMonitor's REST API.
        .PARAMETER AccountName
            Mandatory parameter. Represents the subdomain of the LogicMonitor customer.
        .PARAMETER CollectorID
            Represents the ID number of the desired collector. If no ID is provided and it cannot be found in the registry, the script will exit.
        .PARAMETER CollectorHostName
            Mandatory parameter. Represents the short name of the EDGE Hub.
        .PARAMETER OutputPath
            Mandatory parameter. Represents the path, to which the installer will be downloaded. The default value is $env:TEMP.
        .PARAMETER Async
            When this switch is included, the cmdlet will initiate the download and exit before it is finished. The default behavior is to wait for the download to complete.
        .PARAMETER EventLogSource
            Default value is "LogicMonitorPowershellModule" Represents the name of the desired source, for Event Log logging.
        .PARAMETER BlockLogging
            When this switch is included, the code will write output only to the host and will not attempt to write to the Event Log.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectorInstaller -AccessID <access id> -AccessKey <access key> -Account <account name> -CollectorName "server1""

            In this example, the cmdlet connects to LogicMonitor and downloads the 64-bit Windows installer for collector "server1". The file is saved to C:\users\<username>\AppData\Temp\lmInstaller.exe.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectorInstaller -AccessID <access id> -AccessKey <access key> -Account <account name> -CollectorID 11"

            In this example, the cmdlet connects to LogicMonitor and downloads the 64-bit Windows installer for collector 11. The file is saved to C:\users\<username>\AppData\Temp\lmInstaller.exe.
        .EXAMPLE
            PS C:\> Get-LogicMonitorCollectorInstaller -AccessID <access id> -AccessKey <access key> -Account <account name> -CollectorID 11 -Async"

            In this example, the cmdlet connects to LogicMonitor and downloads the 64-bit Windows installer for collector 11. The file is saved to C:\users\<username>\AppData\Temp\lmInstaller.exe.
            The cmdlet will continue (and exit) while the download is in progress.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")] 
    Param (
        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$AccessId,

        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$AccessKey,

        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$AccountName,

        [Parameter(Mandatory = $True, ParameterSetName = "Default")]
        [int]$CollectorID,

        [Parameter(Mandatory = $True, ParameterSetName = "Name")]
        [string]$CollectorHostName,

        [string]$OutputPath = $env:TEMP,

        [switch]$Async,

        [string]$EventLogSource = 'LogicMonitorPowershellModule',

        [switch]$BlockLogging
    )

    If (-NOT($BlockLogging)) {
        $return = Add-EventLogSource -EventLogSource $EventLogSource
    
        If ($return -ne "Success") {
            $message = ("{0}: Unable to add event source ({1}). No logging will be performed." -f (Get-Date -Format s), $EventLogSource)
            Write-Host $message -ForegroundColor Yellow;

            $BlockLogging = $True
        }
    }

    $message = ("{0}: Beginning {1}." -f (Get-Date -Format s), $MyInvocation.MyCommand)
    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
    
    # Initialize variables.
    $hklm = 'HKLM:\SYSTEM\CurrentControlSet\Control'
    $httpVerb = "GET" # Define what HTTP operation will the script run.
    $data = ''
    $AllProtocols = [System.Net.SecurityProtocolType]'Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    $OutputPath = $OutputPath.TrimEnd("\")

    Switch ($PsCmdlet.ParameterSetName) {
        Default {
            $resourcePath = "/setting/collectors/$CollectorID/installers/Win64"
        }
        Name {
            Try {
                $message = ("{0}: Searching the registry for {1}'s collectorID." -f (Get-Date -Format s), $CollectorHostName)
                If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                [int]$collectorId = (Get-ItemProperty -Path $hklm -Name LogicMonitorCollectorID -ErrorAction Stop).LogicMonitorCollectorID
            }
            Catch {
                $message = ("{0}: Failed to retrieve the collector Id from the registry. The specific error is: {1}" -f (Get-Date -Format s), $_.Exception.Message)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Yellow} Else {Write-Host $message -ForegroundColor Yellow; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Warning -Message $message -EventId 5417}

                Try {
                    $message = ("{0}: Attempting to retrieve the collector ID from LogicMonitor." -f (Get-Date -Format s), $_.Exception.Message)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}
                        
                    # LogicMonitor for the collector hostname and return the id property value, for the one collector matching the desired hostname.
                    $collector = Get-LogicMonitorCollectors -AccessId $AccessId -AccessKey $AccessKey -AccountName $AccountName -CollectorHostname $CollectorHostName
                }
                Catch {
                    $message = ("{0}: Unexpected error retrieving the collector Id from LogicMonitor. To prevent errors, the function Get-LogicMonitorCollectorInstaller will exit. The specific error is: {1}" -f `
                        (Get-Date -Format s), $_.Exception.Message)
                    If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                    Return "Error"
                }
            }

            If ($collector.Id -as [int]) {
                $message = ("{0}: The ID property of {1} is {2}." -f (Get-Date -Format s), $CollectorHostName, $collector.Id)
                If ($BlockLogging) {Write-Verbose $message -ForegroundColor White} Else {Write-Verbose $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                $resourcePath = "/setting/collectors/$($collector.Id)/installers/Win64"
            }
            Else {
                $message = ("{0}: The search of LogicMonitor for {1}'s collector ID value returned a non-number. The value is: {2}. To prevent errors, the {3} function will exit." -f `
                    (Get-Date -Format s), $CollectorHostName, $collector.Id, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }	
        }
    }

    # Construct the query URL.
    $url = "https://$AccountName.logicmonitor.com/santaba/rest$resourcePath"

    # Get current time in milliseconds
    $epoch = [Math]::Round((New-TimeSpan -start (Get-Date -Date "1/1/1970") -end (Get-Date).ToUniversalTime()).TotalMilliseconds)
    
    # Concatenate Request Details
    $requestVars = $httpVerb + $epoch + $data + $resourcePath
    
    # Construct Signature
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($accessKey)
    $signatureBytes = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($requestVars))
    $signatureHex = [System.BitConverter]::ToString($signatureBytes) -replace '-'
    $signature = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($signatureHex.ToLower()))

    # Create the web client object and add headers
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("Authorization", "LMv1 $accessId`:$signature`:$epoch")
    $webClient.Headers.Add("Content-Type", 'application/json')

    # Make Request
    Switch ($Async) {
        $True {
            $message = ("{0}: Beginning download of the LogicMonitor Collector installer to {1}. {2} will continue while the download is in progress." -f (Get-Date -Format s), $OutputPath, $MyInvocation.MyCommand)
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            Try {
                $webClient.DownloadFileAsync($url, "$OutputPath\lmInstaller.exe")
                Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted -SourceIdentifier WebClient.DownloadFileComplete -Action { Unregister-Event -SourceIdentifier WebClient.DownloadFileComplete; $webClient.Dispose(); }
            }
            Catch {
                $message = ("{0}: Unexpected error downloading the LogicMonitor Collector installer. The specific error is: {1}" -f (Get-Date -Format s), $_.Exception.Message)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }

            Return "$OutputPath\lmInstaller.exe"
        }
        $False {
            $message = ("{0}: Beginning download of the LogicMonitor Collector installer to {1}. {2} will continue when the download is complete." -f (Get-Date -Format s), $OutputPath, $MyInvocation.MyCommand)
            If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

            Try {
                $webClient.DownloadFile($url, "$OutputPath\lmInstaller.exe")
                $webClient.Dispose()
            }
            Catch {
                $message = ("{0}: Unexpected error downloading the LogicMonitor Collector installer. The specific error is: {1}" -f (Get-Date -Format s), $_.Exception.Message)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }

            If ((Test-Path -Path "$OutputPath\lmInstaller.exe") -and ((Get-Item -Path "$OutputPath\lmInstaller.exe").Length -gt 10MB)) {
                $message = ("{0}: The LogicMonitor installer was downloaded. Returning the download path." -f (Get-Date -Format s))
                If ($BlockLogging) {Write-Host $message -ForegroundColor White} Else {Write-Host $message -ForegroundColor White; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Information -Message $message -EventId 5417}

                Return "$OutputPath\lmInstaller.exe"
            }
            Else {
                $message = ("{0}: There was no detectable error downloading the LogicMonitor installer, but it is not present in the download location ({1}). To prevent errors, the function {2} will exit" `
                        -f (Get-Date -Format s), $OutputPath, $MyInvocation.MyCommand)
                If ($BlockLogging) {Write-Host $message -ForegroundColor Red} Else {Write-Host $message -ForegroundColor Red; Write-EventLog -LogName Application -Source $eventLogSource -EntryType Error -Message $message -EventId 5417}

                Return "Error"
            }
        }
    }
}
#1.0.0.10