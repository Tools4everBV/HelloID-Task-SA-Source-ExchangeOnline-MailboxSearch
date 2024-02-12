# Warning! When no searchQuery is specified. All mailboxes will be retrieved.
$searchValue = $datasource.searchValue
if ([String]::IsNullOrEmpty($searchValue) -or $searchValue -eq "*") {
    $filter = "*"
}
else {
    $filter = "Name -like '*$searchValue*' -or EmailAddresses -like '*$searchValue*'"
}

# Used to connect to Exchange Online in an unattended scripting scenario using an App ID and App Secret to create an Access Token.
$AADOrganization = $AzureADOrganization
$AADTenantId = $AzureADtenantID
$AADAppID = $AzureADAppId
$AADAppSecret = $AzureADAppSecret

# PowerShell commands to import
$commands = @(
    "Get-Mailbox"
    , "Get-EXOMailbox"
)

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12

$VerbosePreference = "SilentlyContinue"
$InformationPreference = "Continue"
$WarningPreference = "Continue"

#region functions
function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ""
        }
        if ($ErrorObject.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException") {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}

function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if ( $($ErrorObject.Exception.GetType().FullName -eq "Microsoft.PowerShell.Commands.HttpResponseException") -or $($ErrorObject.Exception.GetType().FullName -eq "System.Net.WebException")) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage

            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

try {
    try {           
        # Import module
        $moduleName = "ExchangeOnlineManagement"

        # If module is imported say that and do nothing
        if (Get-Module -Verbose:$false | Where-Object { $_.Name -eq $ModuleName }) {
            Write-Verbose "Module [$ModuleName] is already imported."
        }
        else {
            # If module is not imported, but available on disk then import
            if (Get-Module -ListAvailable -Verbose:$false | Where-Object { $_.Name -eq $ModuleName }) {
                $module = Import-Module $ModuleName -Cmdlet $commands -Verbose:$false
                Write-Verbose "Imported module [$ModuleName]"
            }
            else {
                # If the module is not imported, not available and not in the online gallery then abort
                throw "Module [$ModuleName] is not available. Please install the module using: Install-Module -Name [$ModuleName] -Force"
            }
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
        throw "Error importing module [$ModuleName]. Error Message: $($errorMessage.AuditErrorMessage)"
    }

    # Connect to Exchange
    try {
        # Create access token
        Write-Verbose "Creating Access Token"

        $baseUri = "https://login.microsoftonline.com/"
        $authUri = $baseUri + "$AADTenantId/oauth2/token"
        
        $body = @{
            grant_type    = "client_credentials"
            client_id     = "$AADAppID"
            client_secret = "$AADAppSecret"
            resource      = "https://outlook.office365.com"
        }
        
        $Response = Invoke-RestMethod -Method POST -Uri $authUri -Body $body -ContentType "application/x-www-form-urlencoded" -UseBasicParsing:$true
        $accessToken = $Response.access_token

        # Connect to Exchange Online in an unattended scripting scenario using an access token.
        Write-Verbose "Connecting to Exchange Online"

        $exchangeSessionParams = @{
            Organization     = $AADOrganization
            AppID            = $AADAppID
            AccessToken      = $accessToken
            CommandName      = $commands
            ShowBanner       = $false
            ShowProgress     = $false
            TrackPerformance = $false
            ErrorAction      = "Stop"
        }
        $exchangeSession = Connect-ExchangeOnline @exchangeSessionParams
        
        Write-Information "Successfully connected to Exchange Online"
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage)"
        throw "Error connecting to Exchange Online. Error Message: $($errorMessage.AuditErrorMessage)"
    }

    try {
        $properties = @(
            "Id"
            , "Guid"
            , "DistinguishedName"
            , "Name"
            , "UserPrincipalName"
            , "EmailAddresses"
            , "RecipientTypeDetails"
        )

        $exchangeQuerySplatParams = @{
            ResultSize = "Unlimited"
            Filter     = $filter
        }

        Write-Information "Querying shared mailboxes that match filter [$($exchangeQuerySplatParams.Filter)]"
        $mailboxes = Get-EXOMailbox @exchangeQuerySplatParams | Select-Object $properties

        $mailboxes = $mailboxes | Sort-Object -Property Name
        $resultCount = ($mailboxes | Measure-Object).Count
        Write-Information "Result count: $resultCount"
    
        if ($resultCount -gt 0) {
            foreach ($mailbox in $mailboxes) {
                Write-Output $mailbox
            }
        }
    }
    catch {
        $ex = $PSItem
        $errorMessage = Get-ErrorMessage -ErrorObject $ex

        Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

        throw "Error querying shared mailboxes that match filter [$($exchangeQuerySplatParams.Filter)]. Error Message: $($errorMessage.AuditErrorMessage)"
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($($errorMessage.VerboseErrorMessage))"

    Write-Error "Error querying shared mailboxes that match filter [$($exchangeQuerySplatParams.Filter)]. Error Message: $($errorMessage.AuditErrorMessage)"
}