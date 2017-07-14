#!powershell

# Install NewRelic Infrastructure Windows agent

Invoke-WebRequest "https://download.newrelic.com/infrastructure_agent/windows/newrelic-infra.msi " -OutFile "C:\Temp\newrelic-infra.msi"
start /wait msiexec.exe /qn /i "C:\Temp\newrelic-infra.msi"
echo "licence_key: $env:NEWRELIC_LICENSE_KEY" | Out-File -FilePath "C:\Program Files\New Relic\newrelic-infra\newrelic-infra.yml"
net start newrelic-infra
