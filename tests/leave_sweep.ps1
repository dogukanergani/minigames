<#
.SYNOPSIS
  Oyuncu ayrılma taraması: oyun sırasında farklı anlarda istemci ya da host ayrılır.
.DESCRIPTION
  1v1 oyun, ayrılan işlem `quitafter=S` ile oyun başladıktan S sn sonra aniden çıkar.
  - İstemci ayrılırsa: host kilitlenmemeli; "MAÇ BİTTİ" (rakip takım kalmadı) ya da (ayrılma
    savaştan sonra olduysa) normal "SAVAŞ BİTTİ" yazıp çıkmalı.
  - Host ayrılırsa: istemci kilitlenmemeli; "BAĞLANTI KOPTU: lobiye dönülüyor" yazıp çıkmalı.
  Hiçbir çıktıda SCRIPT ERROR olmamalı. Bu, tests/BULGULAR.md'deki ayrılma hatalarının regresyon testidir.
.EXAMPLE
  ./tests/leave_sweep.ps1
#>
$root = Split-Path $PSScriptRoot -Parent
$g = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "Godot*_console.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $g) { Write-Host "Godot konsol yürütülebilir dosyası bulunamadı." -ForegroundColor Red; exit 2 }
$out = Join-Path ([IO.Path]::GetTempPath()) ("minigames_leave_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Path $out | Out-Null

$failed = 0
function Run-Case([string]$label, [string[]]$hostArgs, [string[]]$clientArgs, [string]$watch, [string]$expect) {
	$base = @("--headless", "--path", $root, "res://scenes/net_test.tscn", "--")
	$h = Start-Process $g -ArgumentList ($base + @("host", "players=2", "auto", "fast", "timeout=30") + $hostArgs) -PassThru -WindowStyle Hidden `
		-RedirectStandardOutput "$out\h.txt" -RedirectStandardError "$out\h.err"
	Start-Sleep -Seconds 2
	$c = Start-Process $g -ArgumentList ($base + @("join", "idx=1", "auto", "fast", "timeout=30") + $clientArgs) -PassThru -WindowStyle Hidden `
		-RedirectStandardOutput "$out\c.txt" -RedirectStandardError "$out\c.err"
	$w = if ($watch -eq "host") { $h } else { $c }
	$t0 = Get-Date
	$w.WaitForExit(70000) | Out-Null
	$sec = [int]((Get-Date) - $t0).TotalSeconds
	$hung = -not $w.HasExited
	foreach ($x in $h, $c) { if (-not $x.HasExited) { $x.Kill() } }
	$file = if ($watch -eq "host") { "$out\h.txt" } else { "$out\c.txt" }
	$line = Get-Content $file -Encoding UTF8 | Select-String $expect | Select-Object -First 1
	$errs = @(Get-Content "$out\h.err", "$out\c.err" -ErrorAction SilentlyContinue | Where-Object { $_ -match "SCRIPT ERROR" }).Count
	$ok = (-not $hung) -and $line -and ($errs -eq 0)
	if ($ok) { Write-Host ("GEÇTİ   {0,-42} {1,3} sn  {2}" -f $label, $sec, $line.Line.Trim()) -ForegroundColor Green }
	else {
		$script:failed++
		Write-Host ("KALDI   {0,-42} {1,3} sn  kilitlendi={2} beklenen-satır-var={3} script-hatası={4}" -f $label, $sec, $hung, [bool]$line, $errs) -ForegroundColor Red
	}
	Start-Sleep -Seconds 2
}

Write-Host "--- İstemci ayrılıyor (host izlenir)"
foreach ($q in 4, 10, 16, 22, 28) { Run-Case "istemci ayrıldı (oyundan $q sn sonra)" @() @("quitafter=$q") "host" "MAÇ BİTTİ|SAVAŞ BİTTİ" }
Write-Host "--- Host ayrılıyor (istemci izlenir)"
foreach ($q in 4, 12, 20) { Run-Case "host ayrıldı (oyundan $q sn sonra)" @("quitafter=$q") @() "client" "BAĞLANTI KOPTU" }
Write-Host "--- Refleks hilesi (GO gelmeden 0 ms yollayan istemci)"
$h = Start-Process $g -ArgumentList @("--headless", "--path", $root, "res://scenes/net_test.tscn", "--", "host", "players=2", "auto", "fast", "timeout=30", "minigame=reaction") -PassThru -WindowStyle Hidden -RedirectStandardOutput "$out\h.txt" -RedirectStandardError "$out\h.err"
Start-Sleep -Seconds 2
$c = Start-Process $g -ArgumentList @("--headless", "--path", $root, "res://scenes/net_test.tscn", "--", "join", "idx=1", "auto", "fast", "timeout=30", "cheat") -PassThru -WindowStyle Hidden -RedirectStandardOutput "$out\c.txt" -RedirectStandardError "$out\c.err"
$h.WaitForExit(90000) | Out-Null; $c.WaitForExit(10000) | Out-Null
foreach ($x in $h, $c) { if (-not $x.HasExited) { $x.Kill() } }
$res = Get-Content "$out\h.txt" -Encoding UTF8 | Select-String "SONUÇ" | Select-Object -First 1
if ($res -and $res.Line -match "erken bastı") { Write-Host ("GEÇTİ   hilekâr istemci 'erken bastı' sayıldı: " + $res.Line.Trim()) -ForegroundColor Green }
else { $failed++; Write-Host "KALDI   hilekâr istemci erken basış sayılmadı: $($res.Line)" -ForegroundColor Red }

Write-Host "--- Tam maç (ilk 2 savaşı kazanan, 2 tur) ve lobiye dönüş"
$h = Start-Process $g -ArgumentList @("--headless", "--path", $root, "res://scenes/net_test.tscn", "--", "host", "players=2", "auto", "fast", "fullmatch", "timeout=30") -PassThru -WindowStyle Hidden -RedirectStandardOutput "$out\h.txt" -RedirectStandardError "$out\h.err"
Start-Sleep -Seconds 2
$c = Start-Process $g -ArgumentList @("--headless", "--path", $root, "res://scenes/net_test.tscn", "--", "join", "idx=1", "auto", "fast", "fullmatch", "timeout=30") -PassThru -WindowStyle Hidden -RedirectStandardOutput "$out\c.txt" -RedirectStandardError "$out\c.err"
$t0 = Get-Date
$h.WaitForExit(240000) | Out-Null; $c.WaitForExit(20000) | Out-Null
$sec = [int]((Get-Date) - $t0).TotalSeconds
$hung = (-not $h.HasExited) -or (-not $c.HasExited)
foreach ($x in $h, $c) { if (-not $x.HasExited) { $x.Kill() } }
$hostOut = @(Get-Content "$out\h.txt" -Encoding UTF8)
$battles = @($hostOut | Where-Object { $_ -match "SAVAŞ BİTTİ: kazanan=" }).Count
$matchEnd = $hostOut | Where-Object { $_ -match "MAÇ BİTTİ: Maç bitti" } | Select-Object -First 1
$cliEnd = Get-Content "$out\c.txt" -Encoding UTF8 | Where-Object { $_ -match "MAÇ BİTTİ: Maç bitti" } | Select-Object -First 1
$errs = @(Get-Content "$out\h.err", "$out\c.err" -ErrorAction SilentlyContinue | Where-Object { $_ -match "SCRIPT ERROR" }).Count
if ((-not $hung) -and $battles -eq 2 -and $matchEnd -and $cliEnd -and $errs -eq 0) {
	Write-Host ("GEÇTİ   tam maç: {0} savaş, {1} sn, {2}" -f $battles, $sec, $matchEnd.Trim()) -ForegroundColor Green
}
else {
	$failed++
	Write-Host ("KALDI   tam maç: kilitlendi={0} savaş-sayısı={1} (beklenen 2) host-maç-sonu={2} istemci-maç-sonu={3} script-hatası={4}" -f $hung, $battles, [bool]$matchEnd, [bool]$cliEnd, $errs) -ForegroundColor Red
}

Write-Host ""
if ($failed -eq 0) { Write-Host "Toplam: hepsi geçti. Çıktılar: $out" -ForegroundColor Green; exit 0 }
Write-Host "Toplam: $failed kaldı. Çıktılar: $out" -ForegroundColor Red; exit 1
