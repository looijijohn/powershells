# Import the Active Directory module
Import-Module ActiveDirectory

# Get the list of all computer names from Active Directory
$computers = Get-ADComputer -Filter * | Select-Object -ExpandProperty Name

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
        $output = Invoke-Command -ComputerName $computer -ScriptBlock {
            $batchCommands = $using:batchCommands
            cmd.exe /c $batchCommands
        } -ErrorAction Stop

        # Split the comma-separated output into fields
        $fields = $output.Trim().Split(',')

        # Verify the output has the expected number of fields (e.g., 5)
        if ($fields.Count -eq 5) {
            # Create a custom object with the parsed data
            $result = [PSCustomObject]@{
                ComputerName   = $computer
                Username       = $fields[0]
                WinVersion     = $fields[1]
                Date           = $fields[2]
                APCcSvcrunning = $fields[3]
                PortFound      = $fields[4]
            }
            # Add the result to the array
            $results += $result
        } else {
            Write-Warning "Unexpected output format from $computer"
        }
    } catch {
        Write-Warning "Failed to run on ${computer}: $_"
    }
}

# Display the results in a table
$results | Format-Table -AutoSize

# Optionally, export the results to a CSV file
$results | Export-Csv -Path ".\batch_output.csv" -NoTypeInformation