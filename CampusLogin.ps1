#requires -Version 5.1
<#
One-shot campus authentication. Never stores a portal query or plaintext password.
Exit codes: 0 online; 10 target Wi-Fi absent; 11 no trusted fresh portal;
20 CheckOnly: authentication needed and supported; 21 manual authentication needed;
22 configuration/credential error; 23 authentication rejected; 24 accepted but unverified;
25 request/protocol failure; 26 another instance is running.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = '',
    [string]$CredentialPath = '',
    [switch]$CheckOnly,
    [switch]$NoWait,
    [switch]$LibraryOnly
)

$script:CampusScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ConfigPath -eq '') { $ConfigPath = Join-Path $script:CampusScriptDirectory 'config.json' }
if ($CredentialPath -eq '') { $CredentialPath = Join-Path $script:CampusScriptDirectory 'credential.xml' }
$script:CampusPortalHost = '10.20.21.2'
$script:CampusProbeUri = [uri]'http://www.msftconnecttest.com/connecttest.txt'
$script:CampusDeadline = $null
$script:CampusCookieJar = New-Object System.Net.CookieContainer
$script:CampusLogPath = Join-Path $script:CampusScriptDirectory 'campus-login.log'

function Write-CampusStatus {
    param([int]$Code, [string]$Message)
    # Callers use constant messages only: no server responses, URLs, or exception text.
    Write-Host $Message
    try {
        if ((Test-Path -LiteralPath $script:CampusLogPath) -and
            (Get-Item -LiteralPath $script:CampusLogPath).Length -gt 65536) {
            Move-Item -LiteralPath $script:CampusLogPath -Destination ($script:CampusLogPath + '.1') -Force
        }
        Add-Content -LiteralPath $script:CampusLogPath -Encoding UTF8 -Value (
            '{0} code={1} {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Code, $Message)
    } catch { }
}

function Get-CampusProperty {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) {
        return $Object.PSObject.Properties[$Name].Value
    }
    return $null
}

function Get-CampusSsid {
    # SSID is also spelled SSID in localized netsh output. BSSID must not match.
    try {
        $lines = @(& "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>$null)
        foreach ($line in $lines) {
            if ($line -match '^\s*SSID\s*:\s*(.*?)\s*$') { $Matches[1] }
        }
    } catch { }
}

function Test-CampusConnection {
    param([string]$ExpectedSsid)
    $ssids = @(Get-CampusSsid)
    foreach ($ssid in $ssids) {
        if ([string]::Equals($ssid, $ExpectedSsid, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function ConvertTo-CampusComponent {
    param([AllowEmptyString()][string]$Value)
    # Match JavaScript encodeURIComponent, including its five unescaped characters.
    $encoded = [uri]::EscapeDataString($Value)
    return $encoded.Replace('%21','!').Replace('%27',"'").Replace('%28','(').Replace('%29',')').Replace('%2A','*')
}

function ConvertTo-CampusDoubleComponent {
    param([AllowEmptyString()][string]$Value)
    return ConvertTo-CampusComponent (ConvertTo-CampusComponent $Value)
}

function Test-CampusPortalUri {
    param([uri]$Uri, [switch]$RequireQuery)
    if ($null -eq $Uri -or -not $Uri.IsAbsoluteUri) { return $false }
    if ($Uri.Scheme -cne 'http' -or $Uri.Host -cne $script:CampusPortalHost -or
        $Uri.Port -ne 80 -or $Uri.UserInfo -ne '' -or $Uri.Fragment -ne '' -or
        $Uri.AbsolutePath -cne '/eportal/index.jsp') { return $false }
    if ($RequireQuery -and $Uri.Query.Length -le 1) { return $false }
    return $true
}

function Invoke-CampusHttp {
    param([uri]$Uri, [ValidateSet('GET','POST')][string]$Method = 'GET',
          [AllowEmptyString()][string]$Body = '')
    # No proxy, automatic redirects, default credentials, or system configuration changes.
    $isPortal = ($Uri.Host -ceq $script:CampusPortalHost -and $Uri.Port -eq 80)
    $isProbe = ($Uri.AbsoluteUri -ceq $script:CampusProbeUri.AbsoluteUri)
    if ($Uri.Scheme -cne 'http' -or $Uri.UserInfo -ne '' -or $Uri.Fragment -ne '' -or
        (-not $isPortal -and -not $isProbe)) { throw 'Untrusted request target.' }
    if ($Method -eq 'POST' -and (-not $isPortal -or $Uri.AbsolutePath -cne '/eportal/InterFace.do')) {
        throw 'Untrusted POST target.'
    }
    $timeout = 6000
    if ($null -ne $script:CampusDeadline) {
        $remaining = [int]($script:CampusDeadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($remaining -le 0) { throw 'Request time budget exhausted.' }
        $timeout = [Math]::Min($timeout, $remaining)
    }
    $request = [System.Net.HttpWebRequest]::Create($Uri)
    $request.Proxy = $null
    $request.AllowAutoRedirect = $false
    $request.UseDefaultCredentials = $false
    $request.PreAuthenticate = $false
    $request.Method = $Method
    $request.Timeout = $timeout
    $request.ReadWriteTimeout = $timeout
    $request.UserAgent = 'CampusNetworkAutoLogin/1.0'
    $request.CookieContainer = $script:CampusCookieJar
    $request.KeepAlive = $false
    $request.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    $response = $null
    try {
        if ($Method -eq 'POST') {
            $request.ContentType = 'application/x-www-form-urlencoded; charset=UTF-8'
            $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
            $request.ContentLength = $bytes.Length
            $stream = $request.GetRequestStream()
            try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
            [Array]::Clear($bytes, 0, $bytes.Length)
        }
        try { $response = $request.GetResponse() }
        catch [System.Net.WebException] {
            if ($null -eq $_.Exception.Response) { throw 'HTTP request failed.' }
            $response = $_.Exception.Response
        }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try {
            $buffer = New-Object char[] 4096
            $builder = New-Object Text.StringBuilder
            while (($count = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($builder.Length + $count -gt 262144) { throw 'Response exceeds size limit.' }
                [void]$builder.Append($buffer, 0, $count)
                if ($null -ne $script:CampusDeadline -and [DateTime]::UtcNow -ge $script:CampusDeadline) {
                    throw 'Request time budget exhausted.'
                }
            }
            return [pscustomobject]@{ Status = [int]$response.StatusCode; Body = $builder.ToString(); Location = $response.Headers['Location'] }
        } finally { $reader.Dispose() }
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $request.Abort()
    }
}

function Get-CampusRedirect {
    param($Response, [uri]$BaseUri)
    $target = $null
    if ($Response.Status -in @(301,302,303,307,308)) { $target = [string]$Response.Location }
    elseif ($Response.Status -eq 200) {
        $patterns = @(
            '(?is)(?:(?:window|top|self|document)\s*\.\s*)?location(?:\s*\.\s*href)?\s*=\s*(["''])(?<url>.*?)\1',
            '(?is)(?:(?:window|top|self|document)\s*\.\s*)?location\s*\.\s*(?:replace|assign)\s*\(\s*(["''])(?<url>.*?)\1\s*\)'
        )
        foreach ($pattern in $patterns) {
            $match = [regex]::Match([string]$Response.Body, $pattern)
            if ($match.Success) { $target = $match.Groups['url'].Value; break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($target) -or $target.Length -gt 16384) { return $null }
    # Decode only literal JS slash/ampersand escapes, never execute JavaScript.
    $target = [System.Net.WebUtility]::HtmlDecode($target)
    $target = $target.Replace('\/', '/').Replace('\u0026', '&').Replace('\x26', '&')
    try { return [uri]::new($BaseUri, $target) } catch { return $null }
}

function Find-CampusPortal {
    $uri = $script:CampusProbeUri
    # At most four redirect hops; only the fixed probe and portal host may be contacted.
    for ($hop = 0; $hop -le 4; $hop++) {
        if (Test-CampusPortalUri $uri -RequireQuery) {
            return [pscustomobject]@{ State = 'Portal'; Uri = $uri }
        }
        $response = Invoke-CampusHttp $uri
        if ($hop -eq 0 -and $response.Status -eq 200 -and $response.Body -ceq 'Microsoft Connect Test') {
            return [pscustomobject]@{ State = 'Online'; Uri = $null }
        }
        $nextUri = Get-CampusRedirect $response $uri
        if ($null -eq $nextUri -or $hop -eq 4) { break }
        if ($nextUri.Scheme -cne 'http' -or $nextUri.Host -cne $script:CampusPortalHost -or
            $nextUri.Port -ne 80 -or $nextUri.UserInfo -ne '' -or $nextUri.Fragment -ne '') { break }
        $uri = $nextUri
    }
    return [pscustomobject]@{ State = 'Unavailable'; Uri = $null }
}

function Invoke-CampusApi {
    param([ValidateSet('pageInfo','getServices','login')][string]$Method,
          [AllowEmptyString()][string]$Body = '', [AllowEmptyString()][string]$Query = '')
    $url = 'http://' + $script:CampusPortalHost + '/eportal/InterFace.do?method=' + $Method
    if ($Method -eq 'getServices') { $url += '&queryString=' + (ConvertTo-CampusComponent $Query) }
    $response = Invoke-CampusHttp -Uri ([uri]$url) -Method POST -Body $Body
    if ($response.Status -ne 200) { throw 'Portal API failed or redirected.' }
    try { return ConvertFrom-Json -InputObject $response.Body -ErrorAction Stop }
    catch { throw 'Portal API returned unsupported data.' }
}

function Get-CampusService {
    param($Services, [AllowEmptyString()][string]$ConfiguredService)
    if ([string](Get-CampusProperty $Services 'isService') -ceq 'false') {
        if ($ConfiguredService -ne '') { throw 'Configured service conflicts with portal.' }
        return ''
    }
    # A changed service selection needs explicit configuration, never an arbitrary first option.
    if ($ConfiguredService -eq '') { throw 'Service selection requires configuration.' }
    $entries = Get-CampusProperty $Services 'services'
    if ($entries -is [string]) { $entries = ConvertFrom-Json -InputObject $entries -ErrorAction Stop }
    foreach ($entry in @($entries)) {
        if ([string](Get-CampusProperty $entry 'serviceName') -ceq $ConfiguredService) {
            foreach ($field in @('isNoOperatorPwd','isNoOperatorPassword','isNoOperatorUserId','operatorPassword')) {
                if ([string](Get-CampusProperty $entry $field) -eq 'true') { throw 'Operator authentication is unsupported.' }
            }
            if (-not [string]::IsNullOrEmpty([string](Get-CampusProperty $entry 'domainName'))) {
                throw 'Domain-specific authentication is unsupported.'
            }
            return $ConfiguredService
        }
    }
    throw 'Configured service is unavailable.'
}

function New-CampusLoginBody {
    param([string]$UserName, [string]$Password, [AllowEmptyString()][string]$Service, [string]$Query)
    # Verified against login_bch.js doauthen(): all four fields are encoded TWICE.
    return ('userId={0}&password={1}&service={2}&queryString={3}&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false' -f
        (ConvertTo-CampusDoubleComponent $UserName), (ConvertTo-CampusDoubleComponent $Password),
        (ConvertTo-CampusDoubleComponent $Service), (ConvertTo-CampusDoubleComponent $Query))
}

function Invoke-CampusLoginMain {
    $script:CampusDeadline = [DateTime]::UtcNow.AddSeconds(90)
    $script:CampusCookieJar = New-Object System.Net.CookieContainer
    try {
        $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $ssid = [string](Get-CampusProperty $config 'SSID')
        $portal = [string](Get-CampusProperty $config 'PortalHost')
        if ($ssid -cne 'Fzdxkjy-web' -or $portal -cne $script:CampusPortalHost) { throw 'Unexpected network configuration.' }
        $configuredService = [string](Get-CampusProperty $config 'Service')
    } catch { Write-CampusStatus 22 'Configuration missing or invalid.'; return 22 }

    $discovery = $null
    $lastCode = 10
    do {
        if (Test-CampusConnection $ssid) {
            $lastCode = 11
            try { $discovery = Find-CampusPortal } catch { $discovery = $null }
            if ($null -ne $discovery -and $discovery.State -eq 'Online') {
                Write-CampusStatus 0 'Internet is already available; no authentication sent.'; return 0
            }
            if ($null -ne $discovery -and $discovery.State -eq 'Portal') { break }
        }
        if ($NoWait -or [DateTime]::UtcNow.AddSeconds(3) -ge $script:CampusDeadline) { break }
        Start-Sleep -Seconds 3
    } while ([DateTime]::UtcNow -lt $script:CampusDeadline)
    if ($null -eq $discovery -or $discovery.State -ne 'Portal') {
        if ($lastCode -eq 10) { Write-CampusStatus 10 'Target campus Wi-Fi is not connected.' }
        else { Write-CampusStatus 11 'No trusted fresh campus authentication redirect was found.' }
        return $lastCode
    }

    # Uri.Query preserves the escaped original query. Remove only its initial question mark.
    $query = $discovery.Uri.Query.Substring(1)
    try {
        $page = Invoke-CampusApi pageInfo -Body ('queryString=' + (ConvertTo-CampusComponent $query))
        $services = Invoke-CampusApi getServices -Query $query
    } catch { Write-CampusStatus 25 'Could not read current portal configuration.'; return 25 }
    # Fail closed if the server changes its authentication requirements.
    if ([string](Get-CampusProperty $page 'passwordEncrypt') -cne 'false' -or
        $null -eq $page.PSObject.Properties['validCodeUrl'] -or
        -not [string]::IsNullOrEmpty([string](Get-CampusProperty $page 'validCodeUrl')) -or
        [string](Get-CampusProperty $page 'isNoOperatorPassword') -eq 'true' -or
        [string](Get-CampusProperty $page 'isNoOperatorUserId') -eq 'true') {
        Write-CampusStatus 21 'Portal requires manual or unsupported authentication.'; return 21
    }
    try { $service = Get-CampusService $services $configuredService }
    catch { Write-CampusStatus 21 'Portal service selection requires manual review.'; return 21 }
    if ($CheckOnly) {
        Write-CampusStatus 20 'CheckOnly: supported campus authentication is required; credentials were not read.'; return 20
    }
    # Re-check the network immediately before reading credentials or sending authentication.
    if (-not (Test-CampusConnection $ssid)) { Write-CampusStatus 10 'Campus Wi-Fi changed; authentication cancelled.'; return 10 }
    try {
        $credential = Import-Clixml -LiteralPath $CredentialPath -ErrorAction Stop
        if ($credential -isnot [Management.Automation.PSCredential] -or
            [string]::IsNullOrWhiteSpace($credential.UserName) -or $credential.Password.Length -eq 0) {
            throw 'Invalid credential.'
        }
    } catch { Write-CampusStatus 22 'Saved credentials are missing or cannot be decrypted by this Windows user.'; return 22 }
    $body = $null
    try {
        $plainPassword = $credential.GetNetworkCredential().Password
        $body = New-CampusLoginBody $credential.UserName $plainPassword $service $query
        $plainPassword = $null
        # Exactly one login attempt. No retries, including ambiguous transport failures.
        $result = Invoke-CampusApi login -Body $body
    } catch {
        Write-CampusStatus 25 'Authentication request failed; it was not retried.'; return 25
    } finally { $body = $null; $plainPassword = $null; $credential = $null }
    if ([string](Get-CampusProperty $result 'result') -cne 'success') {
        Write-CampusStatus 23 'Portal did not accept authentication; automatic retries are disabled.'; return 23
    }
    # Verify actual connectivity after success without submitting any more credentials.
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            $probe = Invoke-CampusHttp $script:CampusProbeUri
            if ($probe.Status -eq 200 -and $probe.Body -ceq 'Microsoft Connect Test') {
                Write-CampusStatus 0 'Campus authentication succeeded and Internet access was verified.'; return 0
            }
        } catch { }
        if ($NoWait -or [DateTime]::UtcNow.AddSeconds(2) -ge $script:CampusDeadline) { break }
        Start-Sleep -Seconds 2
    }
    Write-CampusStatus 24 'Portal accepted authentication, but Internet access was not verified.'; return 24
}

if ($LibraryOnly) { return }
$mutex = $null
$ownsMutex = $false
try {
    $mutex = New-Object Threading.Mutex($false, 'Local\CampusNetworkAutoLogin-Fzdxkjy-web')
    try { $ownsMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex = $true }
    if (-not $ownsMutex) { Write-CampusStatus 26 'Another campus login check is already running.'; $code = 26 }
    else { $code = Invoke-CampusLoginMain }
} catch { Write-CampusStatus 25 'Campus login stopped because of an unexpected local error.'; $code = 25 }
finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $code
