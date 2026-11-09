# Show likely private LAN addresses for a direct Syncthing connection.
# This script only reads adapter configuration; it does not change VPN or firewall settings.

$ErrorActionPreference = 'Stop'
$excludedAdapter = 'vpn|radmin|vmware|virtual|hyper-v|wintun|tap|wireguard|loopback|planet'
$candidates = [System.Collections.Generic.List[object]]::new()

try {
    $configurations = Get-NetIPConfiguration
} catch {
    Write-Error 'Could not read Windows network configuration. Run this script in Windows PowerShell.'
    exit 1
}

foreach ($configuration in $configurations) {
    $adapter = Get-NetAdapter -InterfaceIndex $configuration.InterfaceIndex -ErrorAction SilentlyContinue
    $adapterLabel = @(
        [string]$configuration.InterfaceAlias
        [string]$adapter.InterfaceDescription
    ) -join ' '

    if ($adapterLabel -match $excludedAdapter) {
        continue
    }

    if (-not $configuration.IPv4DefaultGateway) {
        continue
    }

    foreach ($address in $configuration.IPv4Address) {
        $parsedAddress = [System.Net.IPAddress]::Parse($address.IPAddress)
        if ($parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            continue
        }

        $bytes = $parsedAddress.GetAddressBytes()
        $isPrivate = ($bytes[0] -eq 10) -or
            (($bytes[0] -eq 172) -and ($bytes[1] -ge 16) -and ($bytes[1] -le 31)) -or
            (($bytes[0] -eq 192) -and ($bytes[1] -eq 168))

        if ($isPrivate) {
            $candidates.Add([pscustomobject]@{
                Adapter = $configuration.InterfaceAlias
                IPv4 = $parsedAddress.IPAddressToString
                SyncthingAddress = "tcp://$($parsedAddress.IPAddressToString):22000"
            })
        }
    }
}

if ($candidates.Count -eq 0) {
    Write-Host 'No private LAN address with a gateway was found. Connect the laptop to Wi-Fi or Ethernet and try again.'
    exit 1
}

$candidates | Sort-Object Adapter, IPv4 | Format-Table -AutoSize
if ($candidates.Count -gt 1) {
    Write-Host 'Choose the row for the same Wi-Fi or LAN as the phone. Do not use a VPN or virtual-network address.'
}
