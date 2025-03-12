# Create session option with a 2-second timeout
$option = New-PSSessionOption -OpenTimeout 8000

# Example loop through computers
$computers = "WIN-HUVO9UDJ1U3", "DESKTOP-7KESEU8", "computer3"  # Replace with your list
foreach ($computer in $computers) {
    try {
        $output = Invoke-Command -ComputerName $computer -ScriptBlock {
            # Your commands here, e.g., Get-Process
            Get-Process
        } -SessionOption $option -ErrorAction Stop
        Write-Output "Output from $computer : $output"
    }
    catch {
        Write-Warning "$computer is offline or unreachable"
    }
}