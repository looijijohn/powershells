# Import the Active Directory module
Import-Module ActiveDirectory

 

# Create session option with a 2-second timeout
$option = New-PSSessionOption -OpenTimeout 10

# Get the list of all computer names and ObjectGUID from Active Directory
$computers = Get-ADComputer -Filter * -Properties ObjectGUID | Select-Object Name, ObjectGUID

# Define the batch commands as a string
$batchCommands = @"
@echo off
set "USERNAME=%username%"
for /f "tokens=2 delims==" %%a in ('wmic os get Caption /value') do set "WIN_VERSION=%%a"
for /f "delims=" %%a in ('date /T') do set "DATE=%%a"

tasklist /fi "imagename eq APCcSvc.exe" | find /i "APCcSvc.exe"
if %errorlevel% == 0 (
    set "APCcSvcrunning=1"
) else (
    set "APCcSvcrunning=0"
)

set "processName=APCcSvc.exe"
set "portFound=false"
for /f "tokens=4 delims=," %%p in ('tasklist /fi "IMAGENAME eq %processName%" /fo csv') do (
    set "pid=%%p"
    netstat -ano | findstr "%%p" > nul
    if %errorlevel% == 0 (
        set "portFound=true"
        goto endLoop
    )
)
:endLoop
echo %USERNAME%,%WIN_VERSION%,%DATE%,%APCcSvcrunning%,%portFound%
"@

# Initialize an array to store the results
$results = @()

# Loop through each computer
foreach ($computer in $computers) {
    try {
        echo $computer
        # Execute the batch commands on the remote computer and capture its output
        $output = Invoke-Command -ComputerName $computer.Name -ScriptBlock {
            $batchCommands = $using:batchCommands
            $tempBatchFile = "C:\temp_batch.bat"
            
            # Create temporary batch file
            $batchCommands | Out-File -FilePath $tempBatchFile -Encoding ASCII -Force
            
            # Execute the batch file and capture output
            $batchOutput = & $tempBatchFile
            
            # Delete the temporary batch file
            Remove-Item -Path $tempBatchFile -Force -ErrorAction SilentlyContinue
            
            # Return the output
            $batchOutput
        } -SessionOption $option -ErrorAction Stop

        # Split the comma-separated output into fields
        $fields = $output.Trim().Split(',')

        # Verify the output has the expected number of fields (e.g., 5)
        if ($fields.Count -eq 5) {
            # Create a custom object with the parsed data, including ObjectGUID
            $result = [PSCustomObject]@{
                ComputerName   = $computer.Name
                ObjectGUID     = $computer.ObjectGUID
                Username       = $fields[0]
                WinVersion     = $fields[1]
                Date           = $fields[2]
                APCcSvcrunning = $fields[3]
                PortFound      = $fields[4]
            }
            # Add the result to the array
            $results += $result
            $results | Format-Table -AutoSize
        } else {
            Write-Warning "Unexpected output format from $($computer.Name)"
        }
    } catch {
        Write-Warning "Failed to run on $($computer.Name): $_"
    }
}

# Display the results in a table
$results | Format-Table -AutoSize

# Optionally, export the results to a CSV file
$results | Export-Csv -Path "./batch_output.csv" -NoTypeInformation