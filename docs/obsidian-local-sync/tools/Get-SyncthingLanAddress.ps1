# Show likely private LAN addresses for a direct Syncthing connection.
# This script only reads adapter configuration; it does not change VPN or firewall settings.

$excludedAdapter = 'vpn|radmin|vmware|virtual|hyper-v|wintun|tap|wireguard|loopback|planet'
$candidates = [System.Collections.Generic.List[object]]::new()

foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    $isWindowsHotspot = $adapter.Description -match '^Microsoft Wi-Fi Direct Virtual Adapter'

    if (-not $isWindowsHotspot -and $adapter.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) {
        continue
    }

    if (-not $isWindowsHotspot -and $adapter.NetworkInterfaceType -notin @(
        [System.Net.NetworkInformation.NetworkInterfaceType]::Ethernet,
        [System.Net.NetworkInformation.NetworkInterfaceType]::Wireless80211
    )) {
        continue
    }

    $properties = $adapter.GetIPProperties()
    if (-not $isWindowsHotspot) {
        if ("$($adapter.Name) $($adapter.Description)" -match $excludedAdapter) {
            continue
        }

        $hasGateway = $properties.GatewayAddresses | Where-Object {
            $_.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork -and
            $_.Address.IPAddressToString -ne '0.0.0.0'
        }
        if (-not $hasGateway) {
            continue
        }
    }

    foreach ($unicastAddress in $properties.UnicastAddresses) {
        $parsedAddress = $unicastAddress.Address
        if ($parsedAddress.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            continue
        }

        $bytes = $parsedAddress.GetAddressBytes()
        $isPrivate = ($bytes[0] -eq 10) -or
            (($bytes[0] -eq 172) -and ($bytes[1] -ge 16) -and ($bytes[1] -le 31)) -or
            (($bytes[0] -eq 192) -and ($bytes[1] -eq 168))

        if ($isPrivate) {
            $candidates.Add([pscustomobject]@{
                Adapter = $adapter.Name
                Status = if ($isWindowsHotspot) { "Windows hotspot ($($adapter.OperationalStatus))" } else { 'LAN' }
                IPv4 = $parsedAddress.IPAddressToString
                SyncthingAddress = "tcp://$($parsedAddress.IPAddressToString):22000"
            })
        }
    }
}

if ($candidates.Count -eq 0) {
    Write-Host 'No private LAN address was found. Connect the laptop to Wi-Fi or Ethernet and try again.'
    exit 1
}

$candidates | Sort-Object @{ Expression = { $_.Status -like 'Windows hotspot*' }; Descending = $true }, Adapter, IPv4 | Format-Table -AutoSize
if ($candidates.Count -gt 1) {
    Write-Host 'When the phone is connected to the laptop hotspot, use the Windows hotspot row. Otherwise use the LAN row for the shared network.'
}
