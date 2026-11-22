<#
.SYNOPSIS
  Tam tur ağ testlerini (host + N istemci) tek komutla çalıştırır ve doğrular.

.DESCRIPTION
  Her senaryo: 1 host + N istemci (ayrı Godot işlemleri, başsız), `auto fast` ile
  lobi -> minigame -> market -> savaş akışını oynar.
  Doğrulamalar (her senaryo için):
    1. Tüm işlemler zaman aşımı olmadan biter, çıkış kodları 0.
    2. Hepsinde aynı "SAVAŞ BİTTİ: kazanan=... skor=..." satırı var.
    3. SONUÇ (sıralama/coin) ve MARKET (envanter/coin) satırları herkeste aynı.
    4. Çıktıda (stdout/stderr) ERROR / SCRIPT ERROR / Node not found / ZAMAN AŞIMI yok.
  Çıkış kodu: 0 hepsi geçti, 1 en az biri kaldı.
  Portlar aynı (7777) olduğu için senaryolar sırayla çalışır.

.EXAMPLE
  ./tests/run_all.ps1                       # tüm senaryolar
  ./tests/run_all.ps1 -Scenario 1v1,2v2     # seçili senaryolar
  ./tests/run_all.ps1 -Keep                 # çıktı klasörünü silme
#>
param(
	[string[]]$Scenario = @(),
	[int]$TimeoutSec = 150,
	[switch]$Keep
)

$ErrorActionPreference = "Stop"
$Scenario = @($Scenario | ForEach-Object { $_ -split "," } | Where-Object { $_ })  # -File ile "a,b" tek parça gelir
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# --- Godot'u bul ---
$g = $env:GODOT
if (-not $g -or -not (Test-Path $g)) {
	$pkg = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
	$g = Get-ChildItem -Path $pkg -Recurse -Filter "Godot_v*_win64_console.exe" -ErrorAction SilentlyContinue |
		Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $g -or -not (Test-Path $g)) {
	Write-Host "Godot bulunamadı. GODOT ortam değişkenini ayarla ya da winget ile kur." -ForegroundColor Red
	exit 2
}
Write-Host "Godot: $g"

# --- Senaryolar ---
# join: istemci başına ek argümanlar. loaddelay/joindelay için bkz. scripts/net_test.gd
$scenarios = [ordered]@{
	"1v1"      = @{ players = 2; host = ""; joins = @("") }
	"2v2"      = @{ players = 4; host = ""; joins = @("", "", "") }
	"3v3"      = @{ players = 6; host = ""; joins = @("", "", "", "", "") }
	# Yarış: biri 3 sn geç bağlanır, biri / host oyun başlayınca sahneyi geç yükler.
	# Faz girişlerindeki "hazırım" el sıkışması tekrar denenmezse boş ekranda takılır.
	"race-late" = @{ race = $true; players = 3; host = ""; joins = @("joindelay=3", "") }
	"race-load" = @{ race = $true; players = 4; host = "loaddelay=1.5"; joins = @("loaddelay=3", "loaddelay=0.5 joindelay=2", "") }
	# Bilinen hata avı (varsayılan çalışmaz, -Scenario leave ile istenir): join3 oyun başlayınca
	# biraz sonra aniden çıkar; kalanların kilitlenmeden bitmesi beklenir. BULGULAR.md'ye bak.
	"leave"    = @{ optional = $true; leaver = "join3"; players = 4; host = ""; joins = @("", "", "quitafter=4") }
}
if ($Scenario.Count -gt 0) {
	foreach ($s in $Scenario) {
		if (-not $scenarios.Contains($s)) { Write-Host "Bilinmeyen senaryo: $s (var olanlar: $($scenarios.Keys -join ', '))" -ForegroundColor Red; exit 2 }
	}
}
else { $Scenario = @($scenarios.Keys | Where-Object { -not $scenarios[$_].optional }) }

$outRoot = Join-Path ([IO.Path]::GetTempPath()) ("minigames_test_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $outRoot | Out-Null
Write-Host "Çıktı klasörü: $outRoot"

function Start-Godot([string]$name, [string[]]$userArgs, [string]$dir) {
	$a = @("--headless", "--path", $root, "res://scenes/net_test.tscn", "--") + $userArgs
	$p = Start-Process $g -ArgumentList $a -PassThru -WindowStyle Hidden `
		-RedirectStandardOutput (Join-Path $dir "$name.txt") -RedirectStandardError (Join-Path $dir "$name.err")
	$null = $p.Handle  # ExitCode'un okunabilmesi için tutamacı önbelleğe al
	return $p
}

# Satırdan "[main 123] " önekini at (kimlik farkı karşılaştırmayı bozmasın)
function Strip-Prefix([string]$line) { return ($line -replace '^\[main \d+\]\s*', '').Trim() }

function Run-Scenario([string]$name, [hashtable]$sc) {
	$dir = Join-Path $outRoot $name
	New-Item -ItemType Directory -Path $dir | Out-Null
	$fails = New-Object System.Collections.Generic.List[string]
	$procs = [ordered]@{}

	$procs["host"] = Start-Godot "host" (@("host", "players=$($sc.players)", "auto", "fast") + @($sc.host -split " " | Where-Object { $_ })) $dir
	Start-Sleep -Seconds 2
	for ($i = 0; $i -lt $sc.joins.Count; $i++) {
		$n = "join$($i + 1)"
		$procs[$n] = Start-Godot $n (@("join", "idx=$($i + 1)", "auto", "fast") + @($sc.joins[$i] -split " " | Where-Object { $_ })) $dir
	}

	# 1) Hepsi zaman aşımı olmadan bitmeli
	$deadline = (Get-Date).AddSeconds($TimeoutSec)
	while ((Get-Date) -lt $deadline -and ($procs.Values | Where-Object { -not $_.HasExited })) {
		Start-Sleep -Milliseconds 500
	}
	foreach ($k in $procs.Keys) {
		$p = $procs[$k]
		if (-not $p.HasExited -and $sc.leaver -ne $k) {
			$fails.Add("${k}: ${TimeoutSec} sn içinde bitmedi (kilitlendi?)")
			try { $p.Kill() } catch {}
		}
	}
	foreach ($p in $procs.Values) { try { $p.WaitForExit(3000) | Out-Null } catch {} }
	foreach ($k in $procs.Keys) {
		$p = $procs[$k]
		if ($sc.leaver -eq $k) { continue }
		if ($p.HasExited -and $p.ExitCode -ne 0 -and -not ($fails -match "^${k}: .*bitmedi")) {
			$fails.Add("${k}: çıkış kodu $($p.ExitCode)")
		}
	}

	# 2-4) Çıktı doğrulamaları
	$final = @{}; $result = @{}; $market = @{}
	foreach ($k in $procs.Keys) {
		if ($sc.leaver -eq $k) { continue }
		$outFile = Join-Path $dir "$k.txt"; $errFile = Join-Path $dir "$k.err"
		$out = if (Test-Path $outFile) { @(Get-Content $outFile -Encoding UTF8) } else { @() }
		$err = if (Test-Path $errFile) { @(Get-Content $errFile -Encoding UTF8) } else { @() }
		$f = $out | Where-Object { $_ -match "SAVAŞ BİTTİ: kazanan=" } | Select-Object -First 1
		if ($f) { $final[$k] = Strip-Prefix $f } else { $fails.Add("${k}: 'SAVAŞ BİTTİ' satırı yok") }
		$r = $out | Where-Object { $_ -match "\] SONUÇ:" } | Select-Object -First 1
		if ($r) { $result[$k] = Strip-Prefix $r } else { $fails.Add("${k}: 'SONUÇ' satırı yok") }
		$m = $out | Where-Object { $_ -match "\] MARKET:" } | Select-Object -First 1
		if ($m) { $market[$k] = Strip-Prefix $m } else { $fails.Add("${k}: 'MARKET' satırı yok") }
		$bad = @($err) + @($out) | Where-Object { $_ -match "SCRIPT ERROR|(^|\s)ERROR:|ZAMAN AŞIMI|Invalid (call|access)|Parse Error" }
		if ($sc.race) {
			# Yarış senaryolarında sahne yüklenmeden gelen RPC'lerin düşmesi beklenen gürültüdür
			# (el sıkışma tekrar dener). Asıl ölçüt: herkes sonunda aynı sonuca ulaştı mı.
			$bad = @($bad | Where-Object { $_ -notmatch 'Node not found|Parameter "node" is null|Failed to get path from RPC|Invalid packet received. Requested node was not found' })
		}
		if ($bad) { $fails.Add("${k}: hata çıktısı -> " + (($bad | Select-Object -First 2) -join " | ")) }
		$warn = $err | Where-Object { $_ -match "^WARNING" } | Select-Object -First 1
		if ($warn) { $script:warnings.Add("${name}/${k}: $warn") }
	}
	foreach ($pair in @(@("SAVAŞ BİTTİ", $final), @("SONUÇ", $result), @("MARKET", $market))) {
		$vals = @($pair[1].Values | Select-Object -Unique)
		if ($vals.Count -gt 1) {
			$fails.Add("$($pair[0]) satırları oyuncular arasında farklı: " + (($pair[1].GetEnumerator() | ForEach-Object { "$($_.Key)=[$($_.Value)]" }) -join " "))
		}
	}
	return [pscustomobject]@{ Name = $name; Fails = $fails; Final = ($final.Values | Select-Object -First 1); Dir = $dir }
}

# Port 7777 sabit: başka bir test/oyun sunucusu (başka oturum dahil) çalışıyorsa çakışır.
# Önce bekler, olmazsa net bir mesajla çıkar (sahte "kaldı" üretmesin).
function Get-ForeignHosts {
	Get-CimInstance Win32_Process -Filter "Name like 'Godot%'" -ErrorAction SilentlyContinue |
		Where-Object { $_.CommandLine -match "net_test\.tscn" -and $_.CommandLine -match "--\s+host" }
}
$mutex = New-Object System.Threading.Mutex($false, "Global\minigames_net_test_7777")
if (-not $mutex.WaitOne([TimeSpan]::FromSeconds(180))) {
	Write-Host "Başka bir run_all.ps1 180 sn içinde bitmedi (port 7777 meşgul)." -ForegroundColor Red; exit 2
}
function Wait-PortFree {
	$until = (Get-Date).AddSeconds(240)
	while (@(Get-ForeignHosts).Count -gt 0 -and (Get-Date) -lt $until) {
		Write-Host "Port 7777'de başka bir host çalışıyor (PID: $((Get-ForeignHosts).ProcessId -join ', ')), bekleniyor..."
		Start-Sleep -Seconds 5
	}
	if (@(Get-ForeignHosts).Count -gt 0) {
		Write-Host "Port 7777'yi tutan başka bir Godot host işlemi var. Kapatıp tekrar dene." -ForegroundColor Red
		$mutex.ReleaseMutex(); exit 2
	}
}

$results = @()
$script:warnings = New-Object System.Collections.Generic.List[string]
$sw = [Diagnostics.Stopwatch]::StartNew()
foreach ($s in $Scenario) {
	Write-Host ("`n=== Senaryo {0} ({1} oyuncu) ===" -f $s, $scenarios[$s].players)
	Wait-PortFree
	$t0 = $sw.Elapsed.TotalSeconds
	$res = Run-Scenario $s $scenarios[$s]
	$dt = [int]($sw.Elapsed.TotalSeconds - $t0)
	if ($res.Fails.Count -eq 0) { Write-Host ("GEÇTI  ({0} sn)  {1}" -f $dt, $res.Final) -ForegroundColor Green }
	else {
		Write-Host ("KALDI  ({0} sn)" -f $dt) -ForegroundColor Red
		$res.Fails | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
	}
	$results += $res
	Start-Sleep -Seconds 1  # port serbest kalsın
}

Write-Host "`n=== ÖZET ==="
$failed = @($results | Where-Object { $_.Fails.Count -gt 0 })
foreach ($r in $results) {
	Write-Host ("{0,-10} {1}" -f $r.Name, $(if ($r.Fails.Count -eq 0) { "GEÇTI" } else { "KALDI" }))
}
if ($script:warnings.Count -gt 0) {
	Write-Host "Uyarılar (başarısızlık sayılmaz):" -ForegroundColor Yellow
	$script:warnings | Select-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
Write-Host ("Toplam: {0} geçti, {1} kaldı ({2} sn)" -f ($results.Count - $failed.Count), $failed.Count, [int]$sw.Elapsed.TotalSeconds)

if ($failed.Count -eq 0 -and -not $Keep) { Remove-Item -Recurse -Force $outRoot }
else { Write-Host "Çıktılar: $outRoot" }
$mutex.ReleaseMutex()
exit $(if ($failed.Count -eq 0) { 0 } else { 1 })
