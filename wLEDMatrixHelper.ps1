param (
    [string]$message,
    [string]$fg,
    [string]$bg,
    [int]$speed,
    [string]$config = "$PSScriptRoot\wledscroller.json",
    [int]$manualMin,
    [int]$manualMax,
    [int]$manualOrange,
    [int]$manualRed,
    [int]$autoMin,
    [int]$autoMax,
    [int]$autoOrange,
    [int]$autoRed,
    [switch]$h
)
$logFile = Join-Path $PSScriptRoot "wledscroller.log"
# ========== HELP SCREEN ==========
if ($h -or $args -contains '-h' -or $args -contains '--help') {
    Write-Host @"
WLED Scroller - Command Line Help

Usage:
  .\wledscroller.ps1 [options]

Options:
  -message         "Text to scroll"
  -fg              "R,G,B" foreground color
  -bg              "R,G,B" background color
  -speed           Scroll speed (0-255)
  -config          Path to config file (default: wledscroller.json)
  -manualMin       Manual counter minimum
  -manualMax       Manual counter maximum
  -manualOrange    Manual green->orange threshold
  -manualRed       Manual orange->red threshold
  -autoMin         Auto counter minimum
  -autoMax         Auto counter maximum
  -autoOrange      Auto green->orange threshold
  -autoRed         Auto orange->red threshold
  -h, --help       Show this help screen

Examples:
  .\wledscroller.ps1 -message "Watt Up" -fg "255,0,0" -speed 150
  .\wledscroller.ps1 -config ".\myconfig.json"

"@
    exit
}

Remove-Variable -Name 'Parse-RGB' -ErrorAction SilentlyContinue
function Write-Log {
    param (
        [string]$msg,
        [string]$level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $logFile -Value "$timestamp [$level] $msg"
}
# ========== CONFIG MANAGEMENT ==========
function Load-Config {
    if (Test-Path $config) {
        return Get-Content $config | ConvertFrom-Json
    } else {
        $default = @{
            defaultMessage = "Scroll Baby!"
            defaultForeground = @(255,160,0)
            defaultBackground = @(0,0,0)
            defaultSpeed = 100
			    deviceIp = "192.168.1.100"
            manualCounter = @{
                min = 0; max = 999
                greenToOrange = 333
                orangeToRed = 666
            }
            autoCounter = @{
                min = 1; max = 99999
                greenToOrange = 33333
                orangeToRed = 66666
            }
        }
        $default | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $config
        return $default
    }
}

function Save-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $config
}

function Parse-RGB($input, $default) {
    try {
        if (-not $input -or ($input -as [string]) -eq "") {
            Write-Log "Invalid or empty RGB input '$input', using default $($default -join ',')" "WARN"
            return $default
        }

        $parts = $input -split "," | ForEach-Object {
            $clean = ($_ -replace '^\s+|\s+$', '')
            [int]$clean
        }

        if ($parts.Count -eq 3 -and $parts -notcontains $null) {
            Write-Log "Parsed RGB '$input' => $($parts -join ',')" "DEBUG"
            return $parts
        } else {
            Write-Log "Invalid RGB string '$input', using default $($default -join ',')" "WARN"
            return $default
        }
    } catch {
        Write-Log "Exception while parsing RGB '$input', using default. Error: $_" "ERROR"
        return $default
    }
}




# ========== COLOR LOGIC ==========
function Get-ColorFromValue($value, $min, $max, $greenToOrange, $orangeToRed) {
    if ($value -lt $greenToOrange) { return @(0,255,0) }
    elseif ($value -lt $orangeToRed) { return @(255,165,0) }
    else { return @(255,0,0) }
}


function Scroll-MessageMenu($cfg) {
    $lastMsg = $cfg.defaultMessage
    $lastFG = $cfg.defaultForeground
    $lastBG = $cfg.defaultBackground
    $lastSpeed = $cfg.defaultSpeed

    do {
        Clear-Host
        Write-Host "========== SCROLLING MESSAGE MODE ==========" -ForegroundColor Cyan
        Write-Host "Last Sent:" -ForegroundColor Gray
        Write-Host " Message   : $lastMsg"
        Write-Host " Foreground: $($lastFG -join ',')"
        Write-Host " Background: $($lastBG -join ',')"
        Write-Host " Speed     : $lastSpeed"
        Write-Host ""
        Write-Host "Enter a new message OR full param string:" -ForegroundColor Yellow
        Write-Host " Format: message | fg | bg | speed"
        Write-Host " Example: Watt Up | 255,0,0 | 0,0,0 | 150"
        Write-Host " Leave parts blank to reuse last values. Type Q to quit."

        $input = Read-Host "Your input"
        if ($input.Trim().ToUpper() -eq "Q") { return }

        try {
            # Actual array preservation and trim per part
$rawParts = $input -split '\|'
$parts = @()
foreach ($part in $rawParts) {
    $parts += ($part -as [string]) -replace '^\s+|\s+$',''
}

Write-Log "Cleaned input parts array: $($parts -join ' | ')" "DEBUG"

$msgStr = if ($parts.Count -ge 1) { $parts[0] } else { $lastMsg }
$fgStr  = if ($parts.Count -ge 2) { $parts[1] } else { "" }
$bgStr  = if ($parts.Count -ge 3) { $parts[2] } else { "" }
$spdStr = if ($parts.Count -ge 4) { $parts[3] } else { "" }

            Write-Log "Cleaned input values: msg='$msgStr', fg='$fgStr', bg='$bgStr', speed='$spdStr'" "DEBUG"

            $fg = if ($fgStr -ne "") { Parse-RGB $fgStr $lastFG } else { $lastFG }
            $bg = if ($bgStr -ne "") { Parse-RGB $bgStr $lastBG } else { $lastBG }
            $spd = if ($spdStr -ne "") { [int]$spdStr } else { $lastSpeed }

            Write-Log "Parsed values: msg=$msgStr, fg=$($fg -join ','), bg=$($bg -join ','), speed=$spd" "DEBUG"

            Send-WLEDMessage $msgStr $fg $bg $spd
            $lastMsg = $msgStr
            $lastFG = $fg
            $lastBG = $bg
            $lastSpeed = $spd
        } catch {
            Write-Log "Exception during input parsing or sending: $($_.Exception.Message)" "ERROR"
            Write-Warning "Oops! Something went wrong. Check the log for glam-splosions 💅"
            Start-Sleep -Seconds 2
        }
    } while ($true)
}






# ========== SEND TO WLED ==========
function Send-WLEDMessage($msg, $fg, $bg, $spd, [switch]$Silent) {
    $colorBlock = @(
        @($fg[0], $fg[1], $fg[2], 0),
        @($bg[0], $bg[1], $bg[2], 0),
        @(0,0,0,0)
    )
    $payload = @{
        seg = @(@{
            n = "$msg"
            col = $colorBlock
            sx = $spd
        })
    } | ConvertTo-Json -Compress -Depth 5

    try {
        Invoke-RestMethod -Uri "http://$($cfg.deviceIp)/json/state" -Method POST -Body $payload -ContentType "application/json" | Out-Null
        if (-not $Silent) {
            Write-Host ""
            Write-Host "=============================================="
            Write-Host " Message sent successfully!"
            Write-Host " Text       : $msg"
            Write-Host " Foreground : $($fg -join ',')"
            Write-Host " Background : $($bg -join ',')"
            Write-Host " Speed      : $spd"
            Write-Host "=============================================="
        }
    } catch {
        Write-Host "ERROR: Failed to send to controller" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkRed
    }
}


# ========== INTERACTIVE UTILITIES ==========
function Get-UserInput($prompt, $default) {
    $input = Read-Host "$prompt (Default: $default)"
    if ($input) {
        return $input
    } else {
        return $default
    }
}
function Get-RGBInput($prompt, $default) {
    $input = Read-Host "$prompt (Default: $($default -join ','))"
    if (-not $input) {
        return $default
    }

    $rgb = $input -split "," | ForEach-Object { [int]$_ }
    if ($rgb.Count -eq 3) {
        return $rgb
    } else {
        return $default
    }
}

# ========== COUNTERS ==========
function Manual-Counter($cfg) {
    $conf = $cfg.manualCounter
    do {
        Clear-Host
        Write-Host "==== MANUAL COUNTER MODE ====" -ForegroundColor Cyan
        $val = Read-Host "Enter a 3-digit number ($($conf.min)-$($conf.max)) or Q to quit"
        if ($val -eq 'Q') { return }
        if ($val -match '^\d{1,3}$') {
            $v = [int]$val
            if ($v -ge $conf.min -and $v -le $conf.max) {
                $color = Get-ColorFromValue $v $conf.min $conf.max $conf.greenToOrange $conf.orangeToRed
                Send-WLEDMessage $v $color $cfg.defaultBackground $cfg.defaultSpeed
            } else {
                Write-Warning "Value out of range"
            }
        }
    } while ($true)
}

function Auto-Counter($cfg) {
    $conf = $cfg.autoCounter
    $i = if ($conf.direction -eq "up") { $conf.min } else { $conf.max }
    $running = $false
    $paused = $false
    $startedOnce = $false

    function Get-IntervalSeconds($unit) {
        switch ($unit) {
            "s" { return 1 }
            "m" { return 60 }
            "h" { return 3600 }
            default { return 1 }
        }
    }

    $interval = Get-IntervalSeconds $conf.unit

    function Show-CounterUI {
        Clear-Host
        Write-Host "==== AUTO COUNTER MODE ====" -ForegroundColor Cyan
        Write-Host ""
        $label = if ($startedOnce) { "Restart" } else { "Start" }
        Write-Host "[S]$label  [P]ause  [X] Reset  [U]nit  [L]imits  [D]irection  [Q]uit"
        Write-Host ""
        Write-Host ("Counter: {0,-5}" -f $i)
        if ($paused) {
            Write-Host "(Paused)" -ForegroundColor DarkYellow
        }
    }

    Show-CounterUI

    while ($true) {
        if ($running -and -not $paused) {
            $color = Get-ColorFromValue $i $conf.min $conf.max $conf.greenToOrange $conf.orangeToRed
            Send-WLEDMessage $i $color $cfg.defaultBackground $cfg.defaultSpeed -Silent
            Start-Sleep -Seconds $interval

            $i = if ($conf.direction -eq "up") { $i + 1 } else { $i - 1 }

            $limitReached = ($conf.direction -eq "up" -and $i -gt $conf.max) -or
                            ($conf.direction -eq "down" -and $i -lt $conf.min)

            if ($limitReached) {
                $paused = $true
                Show-CounterUI
                Write-Host "`nReached the limit. Press [X] to reset or [Q] to quit." -ForegroundColor Yellow
            } else {
                Show-CounterUI
            }
        }

        # Listen for keypresses even when paused or idle
        for ($wait = 0; $wait -lt 10; $wait++) {
            if ([console]::KeyAvailable) {
                $key = [console]::ReadKey($true)
                $char = $key.KeyChar.ToString().ToUpper()

                switch ($char) {
                    'S' {
                        $running = $true
                        $paused = $false
                        $startedOnce = $true
                        $i = if ($conf.direction -eq "up") { $conf.min } else { $conf.max }
                        Show-CounterUI
                    }
                    'P' {
                        if ($running) { $paused = $true; Show-CounterUI }
                    }
                    'X' {
                        $i = if ($conf.direction -eq "up") { $conf.min } else { $conf.max }
                        Show-CounterUI
                    }
                    'U' {
                        $newUnit = Read-Host "Choose unit: (s)econds, (m)inutes, (h)ours"
                        if ($newUnit -in @("s", "m", "h")) {
                            $conf.unit = $newUnit
                            $interval = Get-IntervalSeconds $newUnit
                            Show-CounterUI
                        }
                    }
                    'L' {
                        $conf.min = [int](Read-Host "New min value (current: $($conf.min))")
                        $conf.max = [int](Read-Host "New max value (current: $($conf.max))")
                        Show-CounterUI
                    }
                    'D' {
                        $newDir = Read-Host "Count direction: (up/down)"
                        if ($newDir -in @("up", "down")) {
                            $conf.direction = $newDir
                            Show-CounterUI
                        }
                    }
                    'Q' {
                        $cfg.autoCounter = $conf
                        Save-Config $cfg
                        return
                    }
                }
            }
            Start-Sleep -Milliseconds 100
        }
    }
}






# ========== CONFIG EDIT MENU ==========
function Config-Menu($cfg) {
    do {
        Clear-Host
        Write-Host "========== CONFIG MENU ==========" -ForegroundColor Cyan
		Write-Host "1. Default Message         : $($cfg.defaultMessage)"
		Write-Host "2. Foreground RGB          : $($cfg.defaultForeground -join ',')"
		Write-Host "3. Background RGB          : $($cfg.defaultBackground -join ',')"
		Write-Host "4. Scroll Speed            : $($cfg.defaultSpeed)"
		Write-Host "5. Device IP Address       : $($cfg.deviceIp)"
		Write-Host "6. Manual Thresholds       : Green<$($cfg.manualCounter.greenToOrange), Orange<$($cfg.manualCounter.orangeToRed)"
		Write-Host "7. Auto Thresholds         : Green<$($cfg.autoCounter.greenToOrange), Orange<$($cfg.autoCounter.orangeToRed), Unit=$($cfg.autoCounter.unit), Direction=$($cfg.autoCounter.direction)"
		Write-Host "8. Save and Back"

		switch (Read-Host "Select option to change") {
			"1" { $cfg.defaultMessage = Get-UserInput "New default message" $cfg.defaultMessage }
			"2" { $cfg.defaultForeground = Get-RGBInput "New foreground RGB" $cfg.defaultForeground }
			"3" { $cfg.defaultBackground = Get-RGBInput "New background RGB" $cfg.defaultBackground }
			"4" { $cfg.defaultSpeed = [int](Get-UserInput "New scroll speed" $cfg.defaultSpeed) }
			"5" { $cfg.deviceIp = Get-UserInput "New device IP address" $cfg.deviceIp }
			"6" {
				$cfg.manualCounter.greenToOrange = [int](Get-UserInput "Manual green->orange" $cfg.manualCounter.greenToOrange)
				$cfg.manualCounter.orangeToRed = [int](Get-UserInput "Manual orange->red" $cfg.manualCounter.orangeToRed)
			}
			"7" {
				$cfg.autoCounter.greenToOrange = [int](Get-UserInput "Auto green->orange" $cfg.autoCounter.greenToOrange)
				$cfg.autoCounter.orangeToRed = [int](Get-UserInput "Auto orange->red" $cfg.autoCounter.orangeToRed)
				$cfg.autoCounter.unit = Get-UserInput "Auto counter unit (s/m/h)" $cfg.autoCounter.unit
				$cfg.autoCounter.direction = Get-UserInput "Auto counter direction (up/down)" $cfg.autoCounter.direction
			}
			"8" {
				Save-Config $cfg
				return
			}
		}
    } while ($true)
}

# ========== MAIN MENU ==========
function Show-Menu($cfg) {
    do {
        Clear-Host
        Write-Host "========== JAZZY'S WLED MENU V1.3 ==========" -ForegroundColor Magenta
        Write-Host "1. Quick Message 1 off" -ForegroundColor Cyan
		Write-Host "2. Message Menu(WIP)" -ForegroundColor DarkCyan
        Write-Host "3. Manual Counter (3-digit input)" -ForegroundColor Green
        Write-Host "4. Auto Counter (1 to 99999)" -ForegroundColor DarkGreen
        Write-Host "5. Configure Defaults" -ForegroundColor Yellow
        Write-Host "6. Exit" -ForegroundColor Red

        switch (Read-Host "Choose an option") {
			"1" {
                $msg = Get-UserInput "Message" $cfg.defaultMessage
                $f = Get-RGBInput "Foreground RGB" $cfg.defaultForeground
                $b = Get-RGBInput "Background RGB" $cfg.defaultBackground
                $spd = [int](Get-UserInput "Scroll speed" $cfg.defaultSpeed)
                Send-WLEDMessage $msg $f $b $spd
            }
			"2" { Scroll-MessageMenu $cfg }
            "3" { Manual-Counter $cfg }
            "4" { Auto-Counter $cfg }
            "5" { Config-Menu $cfg }
            "6" { return }
        }
    } while ($true)
}

# ========== LAUNCH ==========
$cfg = Load-Config

if ($MyInvocation.BoundParameters.Count -gt 0 -and -not $h) {
    $mergedMessage = if ($null -ne $message) { $message } else { $cfg.defaultMessage }
    $mergedFG = Parse-RGB $fg $cfg.defaultForeground
    $mergedBG = Parse-RGB $bg $cfg.defaultBackground
    $mergedSpeed = if ($null -ne $speed) { $speed } else { $cfg.defaultSpeed }
    Send-WLEDMessage $mergedMessage $mergedFG $mergedBG $mergedSpeed
    exit
}

Show-Menu $cfg
