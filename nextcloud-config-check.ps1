# =================== CONFIGURAÇÕES =====================

# Versão esperada do Nextcloud Desktop
$versaoEsperada = "3.6.15"
# URL do MSI da versão recomendada do Nextcloud Desktop
$msiUrl = "https://github.com/nextcloud-releases/desktop/releases/download/v3.16.5/Nextcloud-3.16.5-x64.msi"
# Caminho local para baixar o MSI
$msiLocal = "C:\webgenium\installers\Nextcloud-3.16.5-x64.msi"
# Caminho padrão do arquivo de configuração do Nextcloud Desktop
$configPath = "$env:APPDATA\Nextcloud\nextcloud.cfg"
# Caminho onde este script deve ficar instalado
$scriptInstallPath = "C:\webgenium\scripts\nextcloud-config-check.ps1"
# URL deste script no GitHub (para autoatualização)
$selfUrl = "https://raw.githubusercontent.com/webgenium/nextcloud/main/nextcloud-config-check.ps1"

# Configurações obrigatórias em [General]
$generalOptions = @{
    logDebug = "false"
    logExpire = "24"
    launchOnSystemStartup = "true"
}
# Configuração obrigatória em [Nextcloud]
$nextcloudOptions = @{
    autoUpdateCheck = "false"
}

# =================== AUTOATUALIZAÇÃO =====================

Function Update-SelfIfNeeded {
    param (
        [string]$selfUrl,
        [string]$scriptInstallPath
    )
    # Só baixa nova versão se este script estiver no local certo
    if ($MyInvocation.MyCommand.Path -ne $scriptInstallPath) {
        # Copia para local correto e relança
        if (-not (Test-Path (Split-Path $scriptInstallPath))) {
            New-Item -ItemType Directory -Path (Split-Path $scriptInstallPath) | Out-Null
        }
        Copy-Item $MyInvocation.MyCommand.Path $scriptInstallPath -Force
        Write-Host "Script copiado para $scriptInstallPath. Reiniciando..."
        Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptInstallPath`"" -Wait
        exit
    }

    # Faz download do script publicado no GitHub
    try {
        $remote = Invoke-WebRequest -Uri $selfUrl -UseBasicParsing -ErrorAction Stop
        $remoteContent = $remote.Content -replace "`r`n", "`n"
        $localContent = (Get-Content $scriptInstallPath -Raw) -replace "`r`n", "`n"
        if ($remoteContent -ne $localContent) {
            # Substitui por nova versão e executa
            $tmpNew = "$env:TEMP\nextcloud-config-check.ps1"
            Set-Content -Path $tmpNew -Value $remoteContent
            Write-Host "Nova versão encontrada. Atualizando e executando..."
            Copy-Item $tmpNew $scriptInstallPath -Force
            Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptInstallPath`"" -Wait
            exit
        }
    } catch {
        Write-Host "Aviso: Não foi possível verificar/baixar nova versão do script ($_)" -ForegroundColor Yellow
    }
}

Update-SelfIfNeeded -selfUrl $selfUrl -scriptInstallPath $scriptInstallPath

# =================== CHECAGEM DE VERSÃO DO NEXTCLOUD =====================

# Carrega assembly necessário para mostrar popup gráfico
Add-Type -AssemblyName System.Windows.Forms

function Show-Update-Prompt {
    param(
        [string]$versaoAtual,
        [string]$versaoEsperada,
        [string]$msiUrl,
        [string]$msiLocal
    )
    $msg = "A versão do Nextcloud Desktop instalada é $versaoAtual, mas a versão esperada é $versaoEsperada.`nDeseja atualizar agora?"
    $caption = "Atualização do Nextcloud Desktop"
    $result = [System.Windows.Forms.MessageBox]::Show($msg, $caption, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        if (-not (Test-Path $msiLocal)) {
            Write-Host "Baixando instalador do Nextcloud Desktop para $msiLocal ..."
            try {
                Invoke-WebRequest -Uri $msiUrl -OutFile $msiLocal -UseBasicParsing
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Erro ao baixar o instalador de $msiUrl", "Erro download MSI", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                return
            }
        }
        Start-Process $msiLocal
    }
}

# Verifica se o arquivo de configuração existe
if (-not (Test-Path $configPath)) {
    Write-Host "Arquivo de configuração não encontrado em $configPath"
    exit 1
}

# Lê todas as linhas
$lines = Get-Content $configPath
$inSection = $false
$clientVersion = $null

# Procura por clientVersion na seção [General]
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i].Trim()
    if ($line -eq '[General]') {
        $inSection = $true
        continue
    }
    if ($inSection -and $line -match '^\[.+\]$') {
        $inSection = $false
    }
    if ($inSection -and $line -match '^clientVersion\s*=') {
        $clientVersion = ($line -split '=')[1].Trim()
        break
    }
}

if (-not $clientVersion) {
    Write-Host "clientVersion não encontrada em [General] do arquivo de configuração."
    exit 1
}

if ($clientVersion -ne $versaoEsperada) {
    Show-Update-Prompt -versaoAtual $clientVersion -versaoEsperada $versaoEsperada -msiUrl $msiUrl -msiLocal $msiLocal
} else {
    Write-Host "A versão instalada ($clientVersion) é a esperada ($versaoEsperada)."
}

# =================== GARANTE OPÇÕES EM [General] e [Nextcloud] =====================

function Ensure-Option-In-Section {
    param(
        [string[]]$lines,
        [string]$section,
        [hashtable]$desired
    )
    $options = $desired.Keys
    $sectionIndex = -1
    $inSection = $false
    $found = @{}
    foreach ($k in $options) { $found[$k] = $false }

    # Encontrar índice da seção
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -eq "[$section]") {
            $sectionIndex = $i
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match '^\[.+\]$') {
            $inSection = $false
        }
        if ($inSection) {
            foreach ($opt in $options) {
                if ($line -match "^$opt\s*=") {
                    $found[$opt] = $true
                    $v = ($line -split '=')[1].Trim()
                    if ($v -ne $desired[$opt]) {
                        $lines[$i] = "$opt=$($desired[$opt])"
                        Write-Host "Corrigido $opt para $($desired[$opt]) na seção [$section]."
                    }
                }
            }
        }
    }

    # Seção não existe: cria ao final do arquivo
    if ($sectionIndex -eq -1) {
        $lines += ""
        $lines += "[$section]"
        foreach ($opt in $options) {
            $lines += "$opt=$($desired[$opt])"
            Write-Host "Seção [$section] criada com $opt=$($desired[$opt])."
        }
        return $lines
    }

    # Opções não encontradas: adiciona ao final da seção
    foreach ($opt in $options) {
        if (-not $found[$opt]) {
            # Encontrar o fim da seção
            $insertIndex = $sectionIndex + 1
            for ($j = $sectionIndex + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j].Trim() -match '^\[.+\]$') {
                    $insertIndex = $j
                    break
                }
            }
            $lines = $lines[0..($insertIndex-1)] + "$opt=$($desired[$opt])" + $lines[$insertIndex..($lines.Count-1)]
            Write-Host "$opt=$($desired[$opt]) adicionado à seção [$section]."
        }
    }
    return $lines
}

# Garante [Nextcloud] e autoUpdateCheck=false
$lines = Ensure-Option-In-Section $lines "Nextcloud" $nextcloudOptions

# Garante [General] e as três opções requisitadas
$lines = Ensure-Option-In-Section $lines "General" $generalOptions

# Salva o arquivo de volta
Set-Content -Path $configPath -Value $lines

Write-Host "Arquivo atualizado: $configPath"

# =================== FIM =====================
