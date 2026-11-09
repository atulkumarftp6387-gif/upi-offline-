param(
    [ValidateSet(3306, 3307)]
    [int]$MySqlPort = 3306
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$frontendRoot = Join-Path $projectRoot "frontend"

if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
    throw "Maven was not found on PATH. Install Maven 3.9+ and retry."
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm was not found on PATH. Install Node.js 20+ and retry."
}
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    throw "Java was not found on PATH. Install JDK 21 and retry."
}
if (-not (Test-Path (Join-Path $frontendRoot "node_modules\vite"))) {
    throw "Frontend dependencies are missing. Run 'npm install' from the frontend folder first."
}
if (-not (Get-NetTCPConnection -State Listen -LocalPort $MySqlPort -ErrorAction SilentlyContinue)) {
    throw "No MySQL server is listening on port $MySqlPort. Start it with 'docker compose up -d', or pass the active port (for example: .\start-demo.ps1 -MySqlPort 3307)."
}

$javaHome = $env:JAVA_HOME
if ($javaHome -and (Test-Path (Join-Path $javaHome "bin\java.exe"))) {
    $javaExecutable = Join-Path $javaHome "bin\java.exe"
} else {
    $javaExecutable = (Get-Command java).Source
}
$javaVersion = (& $env:ComSpec /c "`"$javaExecutable`" -version 2>&1" | Out-String)
if ($javaVersion -notmatch 'version "21|openjdk 21') {
    $adoptiumPath = Join-Path $env:ProgramFiles "Eclipse Adoptium"
    $installedJdk = Get-ChildItem -Path $adoptiumPath -Directory -Filter "jdk-21*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if (-not $installedJdk) {
        throw "Java 21 is required. Install JDK 21 or set JAVA_HOME to its installation directory."
    }
    $javaHome = $installedJdk.FullName
}

$backendCommand = @"
`$env:JAVA_HOME = '$javaHome'
`$env:PATH = "`$env:JAVA_HOME\bin;`$env:PATH"
`$env:SPRING_DATASOURCE_URL = 'jdbc:mysql://localhost:$MySqlPort/upi_mesh'
Set-Location -LiteralPath '$projectRoot'
mvn spring-boot:run
"@
$frontendCommand = @"
Set-Location -LiteralPath '$frontendRoot'
npm run dev -- --host 127.0.0.1
"@
$backendEncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($backendCommand))
$frontendEncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($frontendCommand))

Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy",
    "Bypass",
    "-EncodedCommand",
    $backendEncodedCommand
)
Start-Process -FilePath "powershell.exe" -ArgumentList @(
    "-NoExit",
    "-ExecutionPolicy",
    "Bypass",
    "-EncodedCommand",
    $frontendEncodedCommand
)

Write-Host "Started backend and dashboard in separate PowerShell windows."
Write-Host "Wait for Spring Boot to report that Tomcat started, then open http://127.0.0.1:5173."
Write-Host "Close each server window or press Ctrl+C in it to stop that server."
