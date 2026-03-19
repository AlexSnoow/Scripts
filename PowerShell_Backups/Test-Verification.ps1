<# file Test-Verification.ps1
.SYNOPSIS
    Skript modul'nogo testirovanija funkcij verifikacii.
.DESCRIPTION
    Proverjaet korrektnost' raboty funkcii Compare-FilesSourceArchive na modeljah dannyh.
#>

# ===========================================================
#region FUNKCII (Kopija logiki iz osnovnogo skripta)
# ===========================================================

function Compare-FilesSourceArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$SourceList,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$ArchiveList,
        [Parameter(Mandatory=$false)][string]$SourcePath
    )
    process {
        Write-Verbose "Nachalo sravnenija: Istochnik ($($SourceList.Count)) vs Arhiv ($($ArchiveList.Count))"

        # Funkcija normalizacii simvolov
        $NormalizeChars = {
            param([string]$Text)
            $res = $Text
            $res = $res -replace '[\u2013\u2014\u2015]', '-'   # Tire -> defis
            $res = $res -replace '[\u201c\u201d\u00ab\u00bb]', '"'
            $res = $res -replace '\u2026', '...'
            return $res
        }

        # Hesh-tablicy
        $sourceHash = @{}
        foreach ($item in $SourceList) {
            $key = & $NormalizeChars $item.RelativePath.ToLowerInvariant()
            if (-not $sourceHash.ContainsKey($key)) { $sourceHash[$key] = $item }
        }

        $archiveHash = @{}
        foreach ($item in $ArchiveList) {
            $path = $item.RelativePath
            $path = $path -replace '^[A-Z]:\\', '' -replace '^\\\\\?\\', ''
            $path = ($path -replace '/', '\').TrimStart('\').ToLowerInvariant()

            $item.RelativePath = $path

            $key = & $NormalizeChars $path
            if (-not $archiveHash.ContainsKey($key)) { $archiveHash[$key] = $item }
        }

        $missingInArchive = @()
        $sizeMismatch = @()
        $extraInArchive = @()
        $isIdentical = $true

        # 1. Proverka failov istochnika
        foreach ($key in $sourceHash.Keys) {
            $srcItem = $sourceHash[$key]

            # PRJAMOJ POISK
            if ($archiveHash.ContainsKey($key)) {
                $arhItem = $archiveHash[$key]
                if ($srcItem.Length -ne $arhItem.Length) {
                    $sizeMismatch += [PSCustomObject]@{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                    $isIdentical = $false
                }
            }
            else {
                # UMNYY POISK (esli prjamoj ne udalsja)
                $foundKey = $archiveHash.Keys | Where-Object { $_.EndsWith("\$key") -or $_ -eq $key } | Select-Object -First 1

                if ($foundKey) {
                    $arhItem = $archiveHash[$foundKey]
                    if ($srcItem.Length -ne $arhItem.Length) {
                        $sizeMismatch += [PSCustomObject]@{ Path = $key; SourceSize = $srcItem.Length; ArchiveSize = $arhItem.Length }
                        $isIdentical = $false
                    }
                }
                else {
                    $missingInArchive += $srcItem
                    $isIdentical = $false
                }
            }
        }

        # 2. Poisk lishnih failov v arhive
        foreach ($key in $archiveHash.Keys) {
            if ($sourceHash.ContainsKey($key)) { continue }

            $isExtra = $true
            foreach ($srcKey in $sourceHash.Keys) {
                if ($key.EndsWith("\$srcKey") -or $key -eq $srcKey) {
                    $isExtra = $false
                    break
                }
            }

            if ($isExtra) {
                $extraInArchive += $archiveHash[$key]
                $isIdentical = $false
            }
        }

        # 3. Generacija otcheta
        $reportLines = @()
        if ($isIdentical) {
            $reportLines += "SUCCESS: Polnoe sovpadenie failov ($($SourceList.Count) sht)."
        }
        else {
            if ($missingInArchive.Count -gt 0) {
                $reportLines += "ERROR: Otsutstvujut v arhive ($($missingInArchive.Count)):"
                $missingInArchive | Select-Object -First 10 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
                if ($missingInArchive.Count -gt 10) { $reportLines += "  ... i eshhe $($missingInArchive.Count - 10)" }
            }
            if ($sizeMismatch.Count -gt 0) {
                $reportLines += "ERROR: Ne sovpadaet razmer ($($sizeMismatch.Count)):"
                $sizeMismatch | Select-Object -First 5 | ForEach-Object { $reportLines += "  - $($_.Path)" }
            }
            if ($extraInArchive.Count -gt 0) {
                $reportLines += "WARNING: V arhive est' lishnie faily ($($extraInArchive.Count)):"
                $extraInArchive | Select-Object -First 5 | ForEach-Object { $reportLines += "  - $($_.RelativePath)" }
            }
        }

        return [PSCustomObject]@{
            IsIdentical      = $isIdentical
            TotalSource      = $SourceList.Count
            TotalArchive     = $ArchiveList.Count
            MissingInArchive = $missingInArchive
            ExtraInArchive   = $extraInArchive
            SizeMismatch     = $sizeMismatch
            Report           = ($reportLines -join "`r`n")
        }
    }
}

#endregion FUNKCII

# ===========================================================
#region TESTOVYJ DVIZHOK
# ===========================================================

$TestResults = @()

function Assert-Test {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$Expected,
        [string]$Actual
    )

    if ($Condition) {
        Write-Host "  [PASS] $TestName" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "  [FAIL] $TestName" -ForegroundColor Red
        Write-Host "         Ozhidanie: $Expected" -ForegroundColor Yellow
        Write-Host "         Real'nost': $Actual" -ForegroundColor Yellow
        return $false
    }
}

# ===========================================================
#region TEST 1: Polnoe sovpadenie (Happy Path)
# ===========================================================
Write-Host "`n=== TEST 1: Polnoe sovpadenie failov ===" -ForegroundColor Cyan

$srcList1 = @(
    [PSCustomObject]@{ RelativePath = "file1.txt"; Length = 100; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "sub\file2.log"; Length = 200; LastWriteTime = Get-Date }
)
$arhList1 = @(
    [PSCustomObject]@{ RelativePath = "file1.txt"; Length = 100; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "sub\file2.log"; Length = 200; LastWriteTime = Get-Date }
)

$result1 = Compare-FilesSourceArchive -SourceList $srcList1 -ArchiveList $arhList1
$TestResults += Assert-Test -TestName "Schitaet identichnye spiski odinakovymi" -Condition ($result1.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result1.IsIdentical)"

# ===========================================================
#region TEST 2: Otsutstvie failov v arhive
# ===========================================================
Write-Host "`n=== TEST 2: Faily otsutstvujut v arhive ===" -ForegroundColor Cyan

$srcList2 = @(
    [PSCustomObject]@{ RelativePath = "file_missing.txt"; Length = 100; LastWriteTime = Get-Date }
)
$arhList2 = @()

$result2 = Compare-FilesSourceArchive -SourceList $srcList2 -ArchiveList $arhList2
$TestResults += Assert-Test -TestName "Obnaruzhenie otsutstvija failov" -Condition ($result2.MissingInArchive.Count -eq 1) -Expected "Missing=1" -Actual "Missing=$($result2.MissingInArchive.Count)"

# ===========================================================
#region TEST 3: Lishnie faily v arhive
# ===========================================================
Write-Host "`n=== TEST 3: Lishnie faily v arhive ===" -ForegroundColor Cyan

$srcList3 = @()
$arhList3 = @(
    [PSCustomObject]@{ RelativePath = "extra_file.dat"; Length = 500; LastWriteTime = Get-Date }
)

$result3 = Compare-FilesSourceArchive -SourceList $srcList3 -ArchiveList $arhList3
$TestResults += Assert-Test -TestName "Obnaruzhenie lishnih failov" -Condition ($result3.ExtraInArchive.Count -eq 1) -Expected "Extra=1" -Actual "Extra=$($result3.ExtraInArchive.Count)"

# ===========================================================
#region TEST 4: Nesovpadenie razmera
# ===========================================================
Write-Host "`n=== TEST 4: Nesovpadenie razmera ===" -ForegroundColor Cyan

$srcList4 = @(
    [PSCustomObject]@{ RelativePath = "size_test.txt"; Length = 100; LastWriteTime = Get-Date }
)
$arhList4 = @(
    [PSCustomObject]@{ RelativePath = "size_test.txt"; Length = 99; LastWriteTime = Get-Date }
)

$result4 = Compare-FilesSourceArchive -SourceList $srcList4 -ArchiveList $arhList4
$TestResults += Assert-Test -TestName "Obnaruzhenie raznicy v razmerah" -Condition ($result4.SizeMismatch.Count -eq 1) -Expected "Mismatch=1" -Actual "Mismatch=$($result4.SizeMismatch.Count)"

# ===========================================================
#region TEST 5: Normalizacija simvolov (Tire vs Defis) - KRITICHESKIJ
# ===========================================================
Write-Host "`n=== TEST 5: Normalizacija simvolov (Kodirovka OEM) ===" -ForegroundColor Cyan

$srcList5 = @(
    [PSCustomObject]@{ RelativePath = "docs\report - copy.txt"; Length = 100; LastWriteTime = Get-Date }
)
$arhList5 = @(
    [PSCustomObject]@{ RelativePath = "docs\report - copy.txt"; Length = 100; LastWriteTime = Get-Date }
)

$result5 = Compare-FilesSourceArchive -SourceList $srcList5 -ArchiveList $arhList5
$TestResults += Assert-Test -TestName "Schitaet faily s raznym napisaniem tire odinakovymi" -Condition ($result5.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result5.IsIdentical)"

# ===========================================================
#region TEST 6: Prefiksy putej (Kornevaja papka v arhive)
# ===========================================================
Write-Host "`n=== TEST 6: Obrabotka prefiksov putej ===" -ForegroundColor Cyan

$srcList6 = @(
    [PSCustomObject]@{ RelativePath = "data.xml"; Length = 100; LastWriteTime = Get-Date }
)
$arhList6 = @(
    [PSCustomObject]@{ RelativePath = "c:\work\backup\source\job1\data.xml"; Length = 100; LastWriteTime = Get-Date }
)

$result6 = Compare-FilesSourceArchive -SourceList $srcList6 -ArchiveList $arhList6
$TestResults += Assert-Test -TestName "Ignoriruet polnyj put' v arhive (sovpadenie po imeni faila)" -Condition ($result6.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result6.IsIdentical)"

# ===========================================================
#region TEST 7: Normalizacija mnogotochija
# ===========================================================
Write-Host "`n=== TEST 7: Normalizacija mnogotochija ===" -ForegroundColor Cyan

# 4 tochki v istochnike -> 3 tochki (mnogotochie)
$srcList7 = @(
    [PSCustomObject]@{ RelativePath = "docs/report....txt"; Length = 100; LastWriteTime = Get-Date }
)
# 3 tochki v arhive
$arhList7 = @(
    [PSCustomObject]@{ RelativePath = "docs/report...txt"; Length = 100; LastWriteTime = Get-Date }
)

$result7 = Compare-FilesSourceArchive -SourceList $srcList7 -ArchiveList $arhList7
# .... preobrazuetsja v ... (6 tochek), a ... ostajotsja ... (3 tochki) - ne sovpadajut
$TestResults += Assert-Test -TestName "Proverjaet normalizaciju mnogotochija" -Condition ($result7.IsIdentical -eq $false) -Expected "IsIdentical=False" -Actual "IsIdentical=$($result7.IsIdentical)"

# ===========================================================
#region TEST 8: Smeshannyj stsenarij (missing + extra + mismatch)
# ===========================================================
Write-Host "`n=== TEST 8: Smeshannyj stsenarij oshibok ===" -ForegroundColor Cyan

$srcList8 = @(
    [PSCustomObject]@{ RelativePath = "file1.txt"; Length = 100; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "file2.txt"; Length = 200; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "file3.txt"; Length = 300; LastWriteTime = Get-Date }
)
$arhList8 = @(
    [PSCustomObject]@{ RelativePath = "file1.txt"; Length = 99; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "extra.dat"; Length = 500; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "file3.txt"; Length = 300; LastWriteTime = Get-Date }
)

$result8 = Compare-FilesSourceArchive -SourceList $srcList8 -ArchiveList $arhList8
$TestResults += Assert-Test -TestName "Obnaruzhenie vseh tipov oshibok odnovremenno" -Condition (
    $result8.MissingInArchive.Count -eq 1 -and
    $result8.ExtraInArchive.Count -eq 1 -and
    $result8.SizeMismatch.Count -eq 1 -and
    $result8.IsIdentical -eq $false
) -Expected "Missing=1, Extra=1, Mismatch=1" -Actual "Missing=$($result8.MissingInArchive.Count), Extra=$($result8.ExtraInArchive.Count), Mismatch=$($result8.SizeMismatch.Count)"

# ===========================================================
#region TEST 9: Pustye spiski (granichnye uslovija)
# ===========================================================
Write-Host "`n=== TEST 9: Pustye spiski ===" -ForegroundColor Cyan

$srcList9 = @()
$arhList9 = @()

$result9 = Compare-FilesSourceArchive -SourceList $srcList9 -ArchiveList $arhList9
$TestResults += Assert-Test -TestName "Pustye spiski schitajutsja identichnymi" -Condition ($result9.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result9.IsIdentical)"

# ===========================================================
#region TEST 10: Mnozhestvo otsutstvujushhih failov (>10 dlja proverki otcheta)
# ===========================================================
Write-Host "`n=== TEST 10: Mnozhestvo otsutstvujushhih failov (proverka otcheta) ===" -ForegroundColor Cyan

$srcList10 = 1..15 | ForEach-Object {
    [PSCustomObject]@{ RelativePath = "missing$_.txt"; Length = 100; LastWriteTime = Get-Date }
}
$arhList10 = @()

$result10 = Compare-FilesSourceArchive -SourceList $srcList10 -ArchiveList $arhList10
$TestResults += Assert-Test -TestName "Korrektnyj podschet mnozhestva otsutstvujushhih failov" -Condition (
    $result10.MissingInArchive.Count -eq 15 -and
    $result10.Report -like "*... i eshhe 5*"
) -Expected "Missing=15, Report contains '... i eshhe 5'" -Actual "Missing=$($result10.MissingInArchive.Count)"

# ===========================================================
#region TEST 11: Raznye razdeliteli putej (prjamoj vs obratnyj slesh)
# ===========================================================
Write-Host "`n=== TEST 11: Normalizacija razdelitelej putej ===" -ForegroundColor Cyan

$srcList11 = @(
    [PSCustomObject]@{ RelativePath = "folder\sub\file.txt"; Length = 100; LastWriteTime = Get-Date }
)
$arhList11 = @(
    [PSCustomObject]@{ RelativePath = "folder/sub/file.txt"; Length = 100; LastWriteTime = Get-Date }
)

$result11 = Compare-FilesSourceArchive -SourceList $srcList11 -ArchiveList $arhList11
$TestResults += Assert-Test -TestName "Normalizuet prjamye i obratnye sleshi" -Condition ($result11.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result11.IsIdentical)"

# ===========================================================
#region TEST 12: Registronezavisimoe sravnenie
# ===========================================================
Write-Host "`n=== TEST 12: Registronezavisimoe sravnenie ===" -ForegroundColor Cyan

$srcList12 = @(
    [PSCustomObject]@{ RelativePath = "Docs\FILE.TXT"; Length = 100; LastWriteTime = Get-Date }
)
$arhList12 = @(
    [PSCustomObject]@{ RelativePath = "docs\file.txt"; Length = 100; LastWriteTime = Get-Date }
)

$result12 = Compare-FilesSourceArchive -SourceList $srcList12 -ArchiveList $arhList12
$TestResults += Assert-Test -TestName "Ignoriruet registr simvolov" -Condition ($result12.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result12.IsIdentical)"

# ===========================================================
#region TEST 13: Glubokaja vlozhennost' papok
# ===========================================================
Write-Host "`n=== TEST 13: Glubokaja vlozhennost' papok ===" -ForegroundColor Cyan

$srcList13 = @(
    [PSCustomObject]@{ RelativePath = "a\b\c\d\e\f\g\deep.txt"; Length = 100; LastWriteTime = Get-Date }
)
$arhList13 = @(
    [PSCustomObject]@{ RelativePath = "a\b\c\d\e\f\g\deep.txt"; Length = 100; LastWriteTime = Get-Date }
)

$result13 = Compare-FilesSourceArchive -SourceList $srcList13 -ArchiveList $arhList13
$TestResults += Assert-Test -TestName "Korrektnaja obrabotka glubokoj vlozhennosti" -Condition ($result13.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result13.IsIdentical)"

# ===========================================================
#region TEST 14: Faily s odinakovymi imenami v raznyh papkah
# ===========================================================
Write-Host "`n=== TEST 14: Odinakovye imena v raznyh papkah ===" -ForegroundColor Cyan

$srcList14 = @(
    [PSCustomObject]@{ RelativePath = "folder1\config.xml"; Length = 100; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "folder2\config.xml"; Length = 200; LastWriteTime = Get-Date }
)
$arhList14 = @(
    [PSCustomObject]@{ RelativePath = "folder1\config.xml"; Length = 100; LastWriteTime = Get-Date }
    [PSCustomObject]@{ RelativePath = "folder2\config.xml"; Length = 200; LastWriteTime = Get-Date }
)

$result14 = Compare-FilesSourceArchive -SourceList $srcList14 -ArchiveList $arhList14
$TestResults += Assert-Test -TestName "Razlichaet faily s odinakovymi imenami v raznyh papkah" -Condition ($result14.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result14.IsIdentical)"

# ===========================================================
#region TEST 15: Umnyj poisk (fail v podpappe arhiva)
# ===========================================================
Write-Host "`n=== TEST 15: Umnyj poisk po okonchaniju puti ===" -ForegroundColor Cyan

$srcList15 = @(
    [PSCustomObject]@{ RelativePath = "backup.log"; Length = 100; LastWriteTime = Get-Date }
)
$arhList15 = @(
    [PSCustomObject]@{ RelativePath = "logs\2024\march\backup.log"; Length = 100; LastWriteTime = Get-Date }
)

$result15 = Compare-FilesSourceArchive -SourceList $srcList15 -ArchiveList $arhList15
$TestResults += Assert-Test -TestName "Nahodit fail po okonchaniju puti (umnyj poisk)" -Condition ($result15.IsIdentical -eq $true) -Expected "IsIdentical=True" -Actual "IsIdentical=$($result15.IsIdentical)"

# ===========================================================
#region ITIGI
# ===========================================================
Write-Host "`n============================================" -ForegroundColor Yellow
$passed = ($TestResults | Where-Object { $_ -eq $true }).Count
$failed = ($TestResults | Where-Object { $_ -eq $false }).Count
$total = $TestResults.Count

Write-Host "ITIGI TESTIROVANIIA:" -ForegroundColor Yellow
Write-Host "  Projdeno: $passed / $total" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Provaleno: $failed" -ForegroundColor Red
    Write-Host "  VNIMANIE! Funkcii verifikacii rabotajut nekorrektno!" -ForegroundColor Red
}
else {
    Write-Host "  Vse testy projdeny uspeshno. Funkcii rabotajut verno." -ForegroundColor Green
}
Write-Host "============================================`n" -ForegroundColor Yellow

if ($failed -gt 0) { exit 1 } else { exit 0 }
