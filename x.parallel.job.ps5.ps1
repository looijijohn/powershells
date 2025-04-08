# x.ps1 (PowerShell 5.1 with Start-Job)
Import-Module ActiveDirectory

$computers = Get-ADComputer -Filter * -Properties ObjectGUID | Select-Object Name, ObjectGUID
$sessionOption = New-PSSessionOption -OpenTimeout 10

$batchCommands = @"
@echo off
set "USERNAME=%username%"
for /f "tokens=2 delims==" %%a in ('wmic os get Caption /value') do set "WIN_VERSION=%%a"
for /f "delims=" %%a in ('date /T') do set "DATE=%%a"
echo %USERNAME%,%WIN_VERSION%,%DATE%
"@

# Split computers into batches of 100
$batchSize = 100
for ($i = 0; $i -lt $computers.Count; $i += $batchSize) {
    $batch = $computers[$i..($i + $batchSize - 1)]
    
    # Process each batch in parallel using Start-Job
    $jobs = @()
    foreach ($computer in $batch) {
        $jobs += Start-Job -ScriptBlock {
            param($computer, $batchCommands, $sessionOption)
            try {
                $output = Invoke-Command -ComputerName $computer.Name -ScriptBlock {
                    param($batchCommands)
                    $tempBatchFile = "C:\temp_batch.bat"
                    $batchCommands | Out-File -FilePath $tempBatchFile -Encoding ASCII -Force
                    $batchOutput = & $tempBatchFile
                    Remove-Item -Path $tempBatchFile -Force -ErrorAction SilentlyContinue
                    $batchOutput
                } -SessionOption $sessionOption -ArgumentList $batchCommands -ErrorAction Stop

                $fields = $output.Trim().Split(',')
                if ($fields.Count -eq 3) {
                    $result = [PSCustomObject]@{
                        ComputerName = $computer.Name
                        ObjectGUID   = $computer.ObjectGUID
                        Username     = $fields[0]
                        WinVersion   = $fields[1]
                        Date         = $fields[2]
                    }
                    $result | ConvertTo-Json -Compress
                } else {
                    $errorResult = [PSCustomObject]@{
                        ComputerName = $computer.Name
                        ObjectGUID   = $computer.ObjectGUID
                        Error        = "Unexpected output format"
                    }
                    $errorResult | ConvertTo-Json -Compress
                }
            } catch {
                $errorResult = [PSCustomObject]@{
                    ComputerName = $computer.Name
                    ObjectGUID   = $computer.ObjectGUID
                    Error        = $_.Exception.Message
                }
                $errorResult | ConvertTo-Json -Compress
            }
        } -ArgumentList $computer, $batchCommands, $sessionOption
    }

    # Wait for all jobs in the batch to complete and output results
    $jobs | Wait-Job | Receive-Job -Keep | ForEach-Object {
        Write-Output $_
    }
    $jobs | Remove-Job
}