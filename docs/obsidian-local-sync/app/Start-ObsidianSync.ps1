Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$script:ConfigCandidates = @(
    (Join-Path $env:LOCALAPPDATA 'Syncthing\config.xml'),
    (Join-Path $env:APPDATA 'Syncthing\config.xml'),
    (Join-Path $env:USERPROFILE '.config\syncthing\config.xml'),
    'D:\AAPS\Syncthing\config.xml'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$script:ConfigPath = $script:ConfigCandidates | Select-Object -First 1
$script:ApiKey = $null
$script:BaseUrl = $null
$script:Folders = @()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Синхронизация Obsidian'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(470, 245)
$form.MinimumSize = New-Object System.Drawing.Size(470, 245)
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Синхронизация заметок Obsidian'
$title.Location = New-Object System.Drawing.Point(22, 18)
$title.Size = New-Object System.Drawing.Size(410, 28)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 13)
$form.Controls.Add($title)

$folderLabel = New-Object System.Windows.Forms.Label
$folderLabel.Text = 'Папка для проверки:'
$folderLabel.Location = New-Object System.Drawing.Point(24, 62)
$folderLabel.Size = New-Object System.Drawing.Size(400, 22)
$form.Controls.Add($folderLabel)

$folderBox = New-Object System.Windows.Forms.ComboBox
$folderBox.Location = New-Object System.Drawing.Point(24, 88)
$folderBox.Size = New-Object System.Drawing.Size(405, 30)
$folderBox.DropDownStyle = 'DropDownList'
$form.Controls.Add($folderBox)

$syncButton = New-Object System.Windows.Forms.Button
$syncButton.Text = 'Синхронизировать сейчас'
$syncButton.Location = New-Object System.Drawing.Point(24, 132)
$syncButton.Size = New-Object System.Drawing.Size(405, 42)
$syncButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$syncButton.ForeColor = [System.Drawing.Color]::White
$syncButton.FlatStyle = 'Flat'
$form.Controls.Add($syncButton)

$status = New-Object System.Windows.Forms.Label
$status.Text = 'Подключаюсь к Syncthing…'
$status.Location = New-Object System.Drawing.Point(24, 183)
$status.Size = New-Object System.Drawing.Size(405, 28)
$status.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($status)

function Read-SyncthingConfig {
    if (-not $script:ConfigPath) {
        throw 'Не найден config.xml Syncthing. Запустите Syncthing один раз и повторите.'
    }

    [xml]$config = Get-Content -LiteralPath $script:ConfigPath -Raw
    $gui = $config.configuration.gui
    $script:ApiKey = [string]$gui.apikey
    if ([string]::IsNullOrWhiteSpace($script:ApiKey)) {
        throw 'В config.xml не найден ключ API Syncthing.'
    }

    $address = [string]$gui.address
    if ([string]::IsNullOrWhiteSpace($address)) { $address = '127.0.0.1:8384' }
    $scheme = if ([string]$gui.tls -eq 'true') { 'https' } else { 'http' }
    if ($address -match '^https?://') {
        $script:BaseUrl = $address.TrimEnd('/')
    } else {
        $script:BaseUrl = "$scheme://$address"
    }
}

function Invoke-SyncthingApi {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Get', 'Post')][string]$Method = 'Get'
    )

    $uri = [Uri]($script:BaseUrl.TrimEnd('/') + $Path)
    if ($uri.Host -notin @('localhost', '127.0.0.1', '::1')) {
        throw 'Для безопасности программа разрешает обращаться только к Syncthing на этом компьютере.'
    }

    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = $Method
    $request.Headers['X-API-Key'] = $script:ApiKey
    $request.Timeout = 2500
    if ($uri.Scheme -eq 'https') {
        $request.ServerCertificateValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback] {
            param($sender, $certificate, $chain, $errors)
            return $true
        }
    }

    try {
        $response = $request.GetResponse()
        try {
            if ($Method -eq 'Post') { return $null }
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            try {
                $body = $reader.ReadToEnd()
                if ($body) { return ($body | ConvertFrom-Json) }
                return $null
            } finally { $reader.Dispose() }
        } finally { $response.Dispose() }
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) { $_.Exception.Response.Dispose() }
        throw
    }
}

function Find-SyncthingExe {
    $candidates = @(
        'D:\AAPS\Syncthing\syncthing.exe',
        (Join-Path $env:ProgramFiles 'Syncthing\syncthing.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Syncthing\syncthing.exe')
    )
    $command = Get-Command 'syncthing.exe' -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Connect-Syncthing {
    Read-SyncthingConfig
    try {
        $null = Invoke-SyncthingApi -Path '/rest/system/ping'
    } catch {
        $exe = Find-SyncthingExe
        if (-not $exe) {
            throw 'Syncthing сейчас не запущен, а файл syncthing.exe не найден. Откройте Syncthing и нажмите «Повторить».'
        }
        Start-Process -FilePath $exe -WindowStyle Hidden | Out-Null
        $connected = $false
        for ($i = 0; $i -lt 12; $i++) {
            Start-Sleep -Milliseconds 750
            try {
                $null = Invoke-SyncthingApi -Path '/rest/system/ping'
                $connected = $true
                break
            } catch { }
        }
        if (-not $connected) { throw 'Syncthing не ответил. Откройте его обычным способом и нажмите «Повторить».' }
    }

    $script:Folders = @(Invoke-SyncthingApi -Path '/rest/config/folders')
    $folderBox.Items.Clear()
    foreach ($folder in $script:Folders) {
        $folderBox.Items.Add([string]$folder.label) | Out-Null
    }
    if ($script:Folders.Count -eq 0) { throw 'В Syncthing ещё не добавлена папка. Сначала добавьте папку хранилища Obsidian.' }

    $preferredIndex = 0
    for ($i = 0; $i -lt $script:Folders.Count; $i++) {
        if ($script:Folders[$i].label -match 'obsidian|dlia') { $preferredIndex = $i; break }
    }
    $folderBox.SelectedIndex = $preferredIndex
    $status.Text = 'Готово. Нажмите кнопку для немедленной проверки папки.'
    $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 70)
    $syncButton.Enabled = $true
}

$syncButton.Enabled = $true
$syncButton.Add_Click({
    try {
        if (-not $script:Folders -or $script:Folders.Count -eq 0) { Connect-Syncthing }
        $index = $folderBox.SelectedIndex
        if ($index -lt 0 -or $index -ge $script:Folders.Count) { throw 'Выберите папку Obsidian.' }
        $folderId = [Uri]::EscapeDataString([string]$script:Folders[$index].id)
        $null = Invoke-SyncthingApi -Path "/rest/db/scan?folder=$folderId" -Method Post
        $status.Text = 'Папка проверяется. Syncthing передаст изменения подключённым устройствам.'
        $status.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 70)
    } catch {
        $status.Text = $_.Exception.Message
        $status.ForeColor = [System.Drawing.Color]::Firebrick
    }
})

$form.Add_Shown({
    try { Connect-Syncthing }
    catch {
        $status.Text = $_.Exception.Message
        $status.ForeColor = [System.Drawing.Color]::Firebrick
        $syncButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
