# start_monitoring.ps1 — sobe o stack de observabilidade da "AI Factory" local
# Exporter (GPU) + Prometheus (coleta) + Grafana (painel). Tudo nativo, sem Docker.
# Uso:  .\start_monitoring.ps1     (rode novamente apos reiniciar o PC)

$dir = "C:\Users\Steph\ai-factory\monitoring"

function SobeSeNecessario($nome, $porta, $exe, $argList, $wd) {
  $up = (Test-NetConnection localhost -Port $porta -WarningAction SilentlyContinue).TcpTestSucceeded
  if ($up) { Write-Host "[ja rodando] $nome (porta $porta)" -ForegroundColor Yellow; return }
  if (-not $exe -or -not (Test-Path $exe)) { Write-Host "[ERRO] nao achei o executavel de $nome" -ForegroundColor Red; return }
  $sp = @{ FilePath = $exe; WindowStyle = 'Hidden' }
  if ($argList -and $argList.Count -gt 0) { $sp.ArgumentList = $argList }
  if ($wd) { $sp.WorkingDirectory = $wd }
  try { Start-Process @sp; Write-Host "[iniciado] $nome (porta $porta)" -ForegroundColor Green }
  catch { Write-Host "[FALHOU] $nome : $($_.Exception.Message)" -ForegroundColor Red }
}

# localiza os executaveis (independente de versao)
$exp   = (Get-ChildItem "$dir\exporter"   -Recurse -Filter 'nvidia_gpu_exporter.exe' -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$prom  = (Get-ChildItem "$dir\prometheus" -Recurse -Filter 'prometheus.exe'          -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$ghome = (Get-ChildItem "$dir\grafana"    -Directory -Filter 'grafana*'              -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
$graf  = if ($ghome) { "$ghome\bin\grafana.exe" } else { $null }

SobeSeNecessario "Exporter GPU" 9835 $exp $null $null
SobeSeNecessario "Prometheus"   9090 $prom @("--config.file=`"$dir\prometheus.yml`"", "--storage.tsdb.path=`"$dir\promdata`"") $null
SobeSeNecessario "Grafana"      3000 $graf @("server", "--homepath=`"$ghome`"") $ghome

Write-Host "`nPainel:  http://localhost:3000  (dashboard 'Nvidia GPU Metrics')" -ForegroundColor Cyan
