Disconnect-MgGraph -ErrorAction SilentlyContinue
$Error.Clear()
Connect-MgGraph -Scopes 'Application.ReadWrite.All' -NoWelcome -Verbose -ErrorAction Continue
Write-Host '---- Errors ----'
$Error | ForEach-Object { $_.Exception.Message }
Write-Host '---- Context ----'
Get-MgContext | Format-List
