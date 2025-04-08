# x.ps1
# Import the Active Directory module (if needed)
Import-Module ActiveDirectory

# Get the list of computers from Active Directory (adjust as per your setup)
$computers = Get-ADComputer -Filter * -Properties ObjectGUID | Select-Object Name, ObjectGUID

# Create a session option with a 2-second (2000 milliseconds) connection timeout
$sessionOption = New-PSSessionOption -OpenTimeout 10

# Define your batch commands
$batchCommands = @"
@echo off
set "USERNAME=%username%"
for /f "tokens=2 delims==" %%a in ('wmic os get Caption /value') do set "WIN_VERSION=%%a"
for /f "delims=" %%a in ('date /T') do set "DATE=%%a"
echo %USERNAME%,%WIN_VERSION%,%DATE%
"@

# Loop through each computer
foreach ($computer in $computers) {
    try {
        # Run Invoke-Command with a 2-second connection timeout
        $output = Invoke-Command -ComputerName $computer.Name -ScriptBlock {
            $batchCommands = $using:batchCommands
            $tempBatchFile = "C:\temp_batch.bat"
            
            # Write batch commands to a temporary file
            $batchCommands | Out-File -FilePath $tempBatchFile -Encoding ASCII -Force
            
            # Execute the batch file and capture output
            $batchOutput = & $tempBatchFile
            
            # Clean up the temporary file
            Remove-Item -Path $tempBatchFile -Force -ErrorAction SilentlyContinue
            
            # Return the output
            $batchOutput
        } -SessionOption $sessionOption -ErrorAction Stop

        # Process the output (example parsing)
        $fields = $output.Trim().Split(',')
        if ($fields.Count -eq 3) { # Adjust based on your expected output
            $result = [PSCustomObject]@{
                ComputerName = $computer.Name
                ObjectGUID   = $computer.ObjectGUID
                Username     = $fields[0]
                WinVersion   = $fields[1]
                Date         = $fields[2]
            }
            # Output the result as JSON immediately
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
        # Output the error as JSON immediately
        $errorResult | ConvertTo-Json -Compress
    }
}