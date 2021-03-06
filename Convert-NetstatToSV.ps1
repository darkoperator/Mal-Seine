<#
.SYNOPSIS
Convert-NetstatToSV.ps1 takes the output from netstat.exe -n -a -o -b and parses
it into delimited format suitable for stack ranking via get-stakrank.ps1.

NOTE: This script is SPECIFICALLY WRITTEN to parse Windows netstat.exe output 
WITH THE -a -o and -b ARGUMENTS! If your data set does not include these args, 
this script's OUTPUT WILL BE WRONG! Yes, -n is optional, but recommended.

.PARAMETER FileNamePattern
Specifies the naming pattern common to the netstat files to be converted.
.PARAMETER Delimiter
Specifies the delimiter character to use for output. Tab is default.
.PARAMETER ToFile
Specifies that output be written to a file matching the FileNamePattern (same path),
but with .tsv or .csv extension depending on delimtier (.tsv is default).
#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [string]$FileNamePattern,
    [Parameter(Mandatory=$False,Position=1)]
        [string]$Delimiter="`t",
    [Parameter(Mandatory=$False,Position=2)]
        [switch]$tofile=$False
)

function Get-Files {
<#
.SYNOPSIS
Returns the list of input files matching the user supplied file name pattern.
Traverses subdirectories.
#>
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [String]$FileNamePattern
)
    Write-Verbose "Entering $($MyInvocation.MyCommand)"
    Write-Verbose "Looking for files matching user supplied pattern, $FileNamePattern"
    Write-Verbose "This process traverses subdirectories so it may take some time."
    $Files = @(ls -r $FileNamePattern | % { $_.FullName })
    if ($Files) {
        Write-Verbose "File(s) matching pattern, ${FileNamePattern}:`n$($Files -join "`n")"
        $Files
    } else {
        Write-Error "No input files were found matching the user supplied pattern, `
            ${FileNamePattern}."
        Write-Verbose "Exiting $($MyInvocation.MyCommand)"
        exit
    }
    Write-Verbose "Exiting $($MyInvocation.MyCommand)"
}

function Convert {
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [String]$File,
    [Parameter(Mandatory=$True,Position=1)]
        [char]$Delimiter
)
    Write-Verbose "Entering $($MyInvocation.MyCommand)"
    Write-Verbose "Processing $File."
    $data = gc $File
    ("Protocol","LocalAddress","LocalPort","ForeignAddress","ForeignPort","State","PId","Component","Process") -join $Delimiter
    foreach($line in $data) {
       if ($line.length -gt 1 -and $line -notmatch "Active |Proto ") {
            $line = $line.trim()
            if ($line.StartsWith("TCP")) {
                $Protocol, $LocalAddress, $ForeignAddress, $State, $ConPId = ($line -split '\s{2,}')
                $Component = $Process = $False
            } elseif ($line.StartsWith("UDP")) { 
                $State = "STATELESS"
                $Protocol, $LocalAddress, $ForeignAddress, $ConPid = ($line -split '\s{2,}')
                $Component = $Process = $False
            } elseif ($line -match "^\[[-_a-zA-Z0-9.]+\.(exe|com|ps1)\]$") {
                $Process = $line
                if ($Component -eq $False) {
                    # No Component given
                    $Component = $Process
                }
            } elseif ($line -match "Can not obtain ownership information") {
                $Process = $Component = $line
            } else {
                # We have the $Component
                $Component = $line
            }
            if ($State -match "TIME_WAIT") {
                $Component = "Not provided"
                $Process = "Not provided"
            }
            if ($Component -and $Process) {
                $LocalAddress, $LocalPort = Get-AddrPort($LocalAddress)
                $ForeignAddress, $ForeignPort = Get-AddrPort($ForeignAddress)
                ($Protocol, $LocalAddress, $LocalPort, $ForeignAddress, $ForeignPort, $State, $ConPid, $Component, $Process) -join $Delimiter
            }
        }
    }
    Write-Verbose "Exiting $($MyInvocation.MyCommand)"
}

function Get-AddrPort {
Param(
    [Parameter(Mandatory=$True,Position=0)]
        [String]$AddrPort
)
    Write-Verbose "Entering $($MyInvocation.MyCommand)"
    Write-Verbose "Processing $AddrPort"
    if ($AddrPort -match '[0-9a-f]*:[0-9a-f]*:[0-9a-f%]*\]:[0-9]+') {
        $Addr, $Port = $AddrPort -split "]:"
        $Addr += "]"
    } else {
        $Addr, $Port = $AddrPort -split ":"
    }
    $Addr, $Port
    Write-Verbose "Exiting $($MyInvocation.MyCommand)"
}

$Files  = Get-Files -FileNamePattern $FileNamePattern

foreach ($File in $Files) {
    $data = Convert $File $Delimiter
    if ($tofile) {
        $path = ls $File
        $outpath = $path.DirectoryName + "\" + $path.BaseName          
        if ($Delimiter -eq "`t") {
            $outpath += ".tsv"
        } elseif ($Delimiter -eq ",") {
            $outpath += ".csv"
        } else {
            $outpath += ".sv"
        }
        Write-Verbose "Writing output to ${outpath}."
        $data | set-content -Encoding Ascii $outpath 
    } else {
        $data
    }
}
