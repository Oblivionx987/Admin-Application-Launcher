# AdminAppLauncher.ps1 – v2.0 (2025‑04‑19)
# -----------------------------------------------------------------------------
# A forward‑looking PowerShell WinForms GUI that lets an administrator launch
# multiple applications elevated.  This version folds in feature requests 1–10:
#   1.  Edit / remove entries in‑GUI   (context‑menu)
#   2.  Visual status feedback          (Status column)
#   3.  Sort & search                   (column sorting + live filter box)
#   4.  Import / export app lists       (JSON)
#   5.  Drag‑and‑drop add               (drop EXE/LNK onto grid)
#   6.  (Removed tray functionality)        
#   7.  Color & icon cues               (row alt‑colors + app icons)
#   8.  Dark‑mode awareness             (registry check → theme switch)
#   9.  Group launch sets               (Group column + filter)
#  10.  Launch ordering with delays     (Delay column; sequential launch)
# -----------------------------------------------------------------------------

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "This script requires PowerShell 5.0 or later."
    exit
}

#region ► SET‑UP & PREREQS ◄
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, Microsoft.VisualBasic

$ErrorActionPreference = 'Stop'
$currentuser = $env:USERNAME
$ConfigPath  = Join-Path $PSScriptRoot 'appconfig.json'

function Test-IsAdmin {
    $wp = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

#endregion

#region ► THEME (Dark / Light) ◄
$dpiAware = [System.Environment]::OSVersion.Version.Major -ge 10
function Get-IsDarkMode {
    try {
        $rk = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        (Get-ItemProperty -Path $rk -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 0
    } catch { $false }
}
$IsDark = Get-IsDarkMode
$BackColor = if ($IsDark) { [Drawing.Color]::FromArgb(30,30,30) } else { [Drawing.SystemColors]::Window }
$ForeColor = if ($IsDark) { [Drawing.Color]::WhiteSmoke } else { [Drawing.SystemColors]::ControlText }
#endregion

#region ► FORM & CONTROLS ◄
$form               = [Windows.Forms.Form]::new()
$form.Text          = "Admin App Launcher - $currentuser"
$form.Size          = [Drawing.Size]::new(960, 580)
$form.StartPosition = 'CenterScreen'
$form.BackColor     = $BackColor
$form.ForeColor     = $ForeColor
$form.MinimumSize   = $form.Size

# --- Countdown Timer -----------------------------------------------------------
# Create a session timeout label with 8-hour countdown
$lblTimer = [Windows.Forms.Label]::new()
$lblTimer.AutoSize = $false
$lblTimer.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblTimer.Location = [Drawing.Point]::new(490, 40)
$lblTimer.Size = [Drawing.Size]::new(250, 20)
$lblTimer.ForeColor = [System.Drawing.Color]::Red
$lblTimer.Font = New-Object System.Drawing.Font($lblTimer.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
$lblTimer.Text = "Session expires in: 08:00:00"
$form.Controls.Add($lblTimer)

# Create a timer control that ticks every second
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000

# Set initial countdown time (8 hours = 28800 seconds)
$script:remainingSeconds = 8 * 60 * 60

# Timer tick event handler
$timer.Add_Tick({
    $script:remainingSeconds--
    
    # Format the time as hh:mm:ss
    $hours = [Math]::Floor($script:remainingSeconds / 3600)
    $minutes = [Math]::Floor(($script:remainingSeconds % 3600) / 60)
    $seconds = $script:remainingSeconds % 60
    # Use string formatting that's compatible with all PowerShell versions
    $timeString = $hours.ToString("00") + ":" + $minutes.ToString("00") + ":" + $seconds.ToString("00")
    
    # Update the label
    $lblTimer.Text = "Session expires in: $timeString"
    
    # Change color to flashing red when less than 5 minutes remain
    if ($script:remainingSeconds -lt 300) {
        if ($lblTimer.ForeColor -eq [System.Drawing.Color]::Red) {
            $lblTimer.ForeColor = [System.Drawing.Color]::White
        } else {
            $lblTimer.ForeColor = [System.Drawing.Color]::Red
        }
    }
    
    # Auto close when time is up
    if ($script:remainingSeconds -le 0) {
        $timer.Stop()
        [System.Windows.Forms.MessageBox]::Show("Session timeout reached. The application will now close.", "Session Expired", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        $form.Close()
    }
})

# Add a reset timer button next to the timer display
$btnResetTimer = [Windows.Forms.Button]@{
    Text='Reset Timer'; 
    Location=[Drawing.Point]::new(745, 39); 
    Size=[Drawing.Size]::new(75, 22);
    Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 8)
}
$btnResetTimer.Add_Click({
    # Reset to 8 hours
    $script:remainingSeconds = 8 * 60 * 60
    $lblTimer.ForeColor = [System.Drawing.Color]::Red
})
$form.Controls.Add($btnResetTimer)

# Start the timer
$timer.Start()

# --- Search / filter box ------------------------------------------------------
$txtSearch               = [Windows.Forms.TextBox]::new()
# Compatibility check for PlaceholderText property (only available in newer .NET Framework versions)
try {
    $txtSearch.PlaceholderText = 'Search / filter...'
} catch {
    # For older systems where PlaceholderText isn't available, create a watermark another way
    $txtSearch.Text = 'Search / filter...'
    $txtSearch.ForeColor = [System.Drawing.Color]::Gray
    $txtSearch.Add_GotFocus({
        if ($this.Text -eq 'Search / filter...' -and $this.ForeColor -eq [System.Drawing.Color]::Gray) {
            $this.Text = ''
            $this.ForeColor = if ($IsDark) { [Drawing.Color]::WhiteSmoke } else { [Drawing.SystemColors]::WindowText }
        }
    })
    $txtSearch.Add_LostFocus({
        if ([string]::IsNullOrEmpty($this.Text)) {
            $this.Text = 'Search / filter...'
            $this.ForeColor = [System.Drawing.Color]::Gray
        }
    })
}
$txtSearch.Location      = [Drawing.Point]::new(10,40)
$txtSearch.Width         = 300
$form.Controls.Add($txtSearch)

# --- Group filter -------------------------------------------------------------
$cboGroup               = [Windows.Forms.ComboBox]::new()
$cboGroup.DropDownStyle = 'DropDownList'
$cboGroup.Items.Add('<All Groups>') | Out-Null
$cboGroup.SelectedIndex = 0
$cboGroup.Location      = [Drawing.Point]::new(320,40)
$cboGroup.Width         = 160
$form.Controls.Add($cboGroup)

# --- Data grid ----------------------------------------------------------------
$grid                 = [Windows.Forms.DataGridView]::new()
$grid.Location        = [Drawing.Point]::new(10,70)
$grid.Size            = [Drawing.Size]::new(920, 390)
$grid.AutoSizeRowsMode= 'AllCells'
$grid.AllowUserToAddRows = $false
$grid.RowHeadersVisible  = $false
$grid.SelectionMode      = 'FullRowSelect'
$grid.AllowDrop          = $true
$grid.EnableHeadersVisualStyles = $false
# ----- Dark-mode styling -------------------------------------------------
if ($IsDark) {
    $grid.DefaultCellStyle.BackColor        = $BackColor      # 30,30,30
    $grid.DefaultCellStyle.ForeColor        = $ForeColor      # WhiteSmoke
    $grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(70,70,70)
    $grid.DefaultCellStyle.SelectionForeColor = $ForeColor
}

$grid.BackgroundColor    = $BackColor
$grid.GridColor          = $ForeColor
$form.Controls.Add($grid)

# Alternating row style for readability
$alt = $grid.AlternatingRowsDefaultCellStyle
$alt.BackColor = if ($IsDark) { [Drawing.Color]::FromArgb(45,45,48) } else { [Drawing.Color]::FromArgb(235,235,235) }
$alt.ForeColor = $ForeColor

# Columns
$columns = @()
$columns += [Windows.Forms.DataGridViewCheckBoxColumn]@{HeaderText='Sel'; Width=35}
$columns += [Windows.Forms.DataGridViewTextBoxColumn]@{HeaderText='Nickname'; Width=160}
$columns += [Windows.Forms.DataGridViewTextBoxColumn]@{HeaderText='Group'; Width=110}
$columns += [Windows.Forms.DataGridViewTextBoxColumn]@{HeaderText='Delay (s)'; Width=70}
$columns += [Windows.Forms.DataGridViewImageColumn]@{HeaderText='Icon'; Width=40}
$columns += [Windows.Forms.DataGridViewTextBoxColumn]@{HeaderText='Path'; Width=360; ReadOnly=$true}
$columns += [Windows.Forms.DataGridViewTextBoxColumn]@{HeaderText='Status'; Width=90; ReadOnly=$true}
$columns += [Windows.Forms.DataGridViewButtonColumn]@{HeaderText='Action'; Text='Start'; UseColumnTextForButtonValue=$true; Width=60}
foreach ($c in $columns){ [void]$grid.Columns.Add($c) }

# --- Buttons ------------------------------------------------------------------
$btnAdd  = [Windows.Forms.Button]@{Text='Add application'; Location=[Drawing.Point]::new(10,470); Size=[Drawing.Size]::new(120,30)}
$btnImport = [Windows.Forms.Button]@{Text='Import'; Location=[Drawing.Point]::new(140,470); Size=[Drawing.Size]::new(70,30)}
$btnExport = [Windows.Forms.Button]@{Text='Export'; Location=[Drawing.Point]::new(220,470); Size=[Drawing.Size]::new(70,30)}
$btnStartSel = [Windows.Forms.Button]@{Text='Start selected'; Location=[Drawing.Point]::new(310,470); Size=[Drawing.Size]::new(110,30)}
$btnClose = [Windows.Forms.Button]@{Text='Close'; Location=[Drawing.Point]::new(430,470); Size=[Drawing.Size]::new(70,30)}
$form.Controls.AddRange(@($btnAdd,$btnImport,$btnExport,$btnStartSel,$btnClose))

# --- Notify icon functionality removed --------------------------------------

#endregion

#region ► CONFIG LOAD / SAVE ◄
function Load-Config {
    if (!(Test-Path $ConfigPath)){ return }
    $json = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $grid.Rows.Clear()
    foreach ($app in $json){ Add-Row $app.Nickname $app.Group $app.Delay $app.Path }
}

function Save-Config {
    $apps = foreach ($row in $grid.Rows){
        if ($row.IsNewRow){ continue }
        [pscustomobject]@{
            Nickname = $row.Cells[1].Value
            Group    = $row.Cells[2].Value
            Delay    = if ([int]::TryParse($row.Cells[3].Value, [ref]$null)) { [int]$row.Cells[3].Value } else { 0 }
            Path     = $row.Cells[5].Value
        }
    }
    $apps | ConvertTo-Json -Depth 2 | Set-Content -Encoding UTF8 $ConfigPath
}
#endregion

#region ► ROW HELPERS ◄
function Get-AppIcon($path){
    try{ [Drawing.Icon]::ExtractAssociatedIcon($path) }catch{ [Drawing.SystemIcons]::Application }
}
function Add-Row([string]$nick,[string]$group,[int]$delay,[string]$path){
    $row = $grid.Rows.Add()
    $grid.Rows[$row].Cells[0].Value = $false  # selected
    $grid.Rows[$row].Cells[1].Value = $nick
    $grid.Rows[$row].Cells[2].Value = $group
    $grid.Rows[$row].Cells[3].Value = $delay
    $grid.Rows[$row].Cells[4].Value = Get-AppIcon $path
    $grid.Rows[$row].Cells[5].Value = $path
    $grid.Rows[$row].Cells[6].Value = ''
}
#endregion

#region ► APP LAUNCH ◄
function Start-App ($row){
    $path  = $row.Cells[5].Value
    if ([string]::IsNullOrEmpty($path) -or ![System.IO.File]::Exists($path)){
        $row.Cells[6].Value = '✗ Missing'
        return
    }
    $row.Cells[6].Value = 'Launching…'
    try{
        if (Test-IsAdmin){
            $p = Start-Process -FilePath $path -PassThru -WindowStyle Normal
        }else{
            $p = Start-Process -FilePath $path -Verb RunAs -PassThru -WindowStyle Normal
        }
        $null = $p.WaitForInputIdle(20000)
        $row.Cells[6].Value = '✓ Launched'
    }catch{
        $row.Cells[6].Value = '✗ Failed'
    }
}
#endregion

#region ► CONTEXT MENU (edit/remove) ◄
$ctx = [Windows.Forms.ContextMenuStrip]::new()
$itemEdit   = $ctx.Items.Add('Edit…')
$itemRemove = $ctx.Items.Add('Remove')
$grid.ContextMenuStrip = $ctx
$grid.Add_MouseDown({ param($s,$e) if($e.Button -eq 'Right'){
        $rowIndex = $grid.HitTest($e.X,$e.Y).RowIndex
        $grid.ClearSelection()
        if($rowIndex -ge 0){
            $grid.Rows[$rowIndex].Selected = $true
            $grid.CurrentCell = $grid.Rows[$rowIndex].Cells[1]
        }
    }})
$itemEdit.Add_Click({
    if(!$grid.CurrentRow){ return }
    $row=$grid.CurrentRow
    $row.ReadOnly=$false   # allow edits to nickname/group/delay
})
$itemRemove.Add_Click({
    if($grid.CurrentRow){ $grid.Rows.Remove($grid.CurrentRow); Save-Config }
})
#endregion

#region ► DRAG‑AND‑DROP support ◄
$grid.Add_DragEnter({ param($s,$e)
    if($e.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)){
        $e.Effect = 'Copy'
    }})
$grid.Add_DragDrop({ param($s,$e)
    $files = $e.Data.GetData([Windows.Forms.DataFormats]::FileDrop)
    foreach($file in $files){
        if($file -match '\\.(lnk|exe)$'){
            $target = if($file.ToLower().EndsWith('.lnk')){
                try {
                    $sh = New-Object -ComObject WScript.Shell
                    $path = $sh.CreateShortcut($file).TargetPath
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null
                    [System.GC]::Collect()
                    $path
                } catch {
                    # If we can't get the shortcut target, use the .lnk file itself
                    $file
                }
            }else{ $file }
            $nick = [System.IO.Path]::GetFileNameWithoutExtension($target)
            Add-Row $nick '' 0 $target
        }
    }
    Save-Config
})
#endregion

#region ► SEARCH & GROUP FILTER ◄
function Apply-Filter{
    $term  = $txtSearch.Text.Trim().ToLower()
    # Skip filtering if the text is just the placeholder
    if ($term -eq 'search / filter...') { $term = '' }
    
    $grp   = if($cboGroup.SelectedIndex -eq 0){ $null } else { $cboGroup.SelectedItem }
    foreach($row in $grid.Rows){
        if($row.IsNewRow){ continue }
        $visible = $true
        if($term){
            $visible = ($row.Cells[1].Value -as [string]).ToLower().Contains($term) -or (($row.Cells[5].Value) -as [string]).ToLower().Contains($term)
        }
        if($grp){ $visible = $visible -and ($row.Cells[2].Value -eq $grp) }
        $row.Visible = $visible
    }
}
$txtSearch.Add_TextChanged({
    # Ignore filter operation when displaying the placeholder text
    if ($txtSearch.Text -eq 'Search / filter...' -and 
        ($txtSearch.ForeColor -eq [System.Drawing.Color]::Gray -or 
         $txtSearch.ForeColor -eq [System.Drawing.SystemColors]::GrayText)) { 
        return 
    }
    Apply-Filter 
})
$cboGroup.Add_SelectedIndexChanged({ Apply-Filter })
#endregion

#region ► BUTTON EVENTS ◄
$btnAdd.Add_Click({
    $dlg = [Windows.Forms.OpenFileDialog]::new()
    $dlg.Filter = 'Executables (*.exe)|*.exe|Shortcuts (*.lnk)|*.lnk|All files (*.*)|*.*'
    if($dlg.ShowDialog() -ne 'OK'){ return }
    $target = if($dlg.FileName.ToLower().EndsWith('.lnk')){
        $sh = New-Object -ComObject WScript.Shell
        try {
            $sh.CreateShortcut($dlg.FileName).TargetPath
        } finally {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null
            [System.GC]::Collect()
        }
    }else{ $dlg.FileName }

    $defaultNick = [IO.Path]::GetFileNameWithoutExtension($target)
    $nick = [Microsoft.VisualBasic.Interaction]::InputBox('Nickname:', 'Add application', $defaultNick)
    if([string]::IsNullOrWhiteSpace($nick)){ return }

    $group = [Microsoft.VisualBasic.Interaction]::InputBox('Group (optional):', 'Group', '')
    $delay = [int][Microsoft.VisualBasic.Interaction]::InputBox('Delay in seconds (0 for none):', 'Delay', '0')
    Add-Row $nick $group $delay $target
    if($group -and !$cboGroup.Items.Contains($group)){ $null = $cboGroup.Items.Add($group) }
    Save-Config
})

$btnImport.Add_Click({
    $dlg=[Windows.Forms.OpenFileDialog]@{Filter='JSON files (*.json)|*.json|All files (*.*)|*.*'}
    if($dlg.ShowDialog() -ne 'OK'){ return }
    try{ Copy-Item $dlg.FileName $ConfigPath -Force; Load-Config; Save-Config }catch{ [Windows.Forms.MessageBox]::Show($_) }
})
$btnExport.Add_Click({
    $dlg=[Windows.Forms.SaveFileDialog]@{Filter='JSON files (*.json)|*.json'; FileName='appconfig_export.json'}
    if($dlg.ShowDialog() -ne 'OK'){ return }
    try{ Save-Config; Copy-Item $ConfigPath $dlg.FileName -Force }catch{ [Windows.Forms.MessageBox]::Show($_) }
})

$btnStartSel.Add_Click({
    # Launch selected rows ordered by Delay ascending
    $rows = $grid.Rows | Where-Object { $_.Cells[0].Value -eq $true -and -not $_.IsNewRow }
    $ordered = $rows | Sort-Object { [int]$_.Cells[3].Value }
    foreach($row in $ordered){
        $delay = [int]$row.Cells[3].Value
        if($delay -gt 0){ $row.Cells[6].Value = "Waiting $delay s…"; Start-Sleep -Seconds $delay }
        Start-App $row
    }
})

$btnClose.Add_Click({ Save-Config; $form.Close() })
#endregion

#region ► GRID BUTTON (per‑row start) ◄
$grid.Add_CellContentClick({ param($s,$e)
    if($e.RowIndex -lt 0){ return }
    if($e.ColumnIndex -eq 7){ Start-App $grid.Rows[$e.RowIndex] }
})
#endregion

#region ► MINIMIZE BEHAVIOR ◄
# Standard window minimize behavior - no code needed
#endregion

#region ► INIT & RUN ◄
Load-Config
# Populate group dropdown
foreach($row in $grid.Rows){ if(-not $row.IsNewRow -and $row.Cells[2].Value -and -not $cboGroup.Items.Contains($row.Cells[2].Value)){ $null=$cboGroup.Items.Add($row.Cells[2].Value) } }

[void]$form.ShowDialog()
Save-Config
#endregion