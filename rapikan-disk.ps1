<#
================================================================================
 rapikan-disk.ps1  -  Bersihkan & rapikan penyimpanan Windows dalam satu file
 Versi   : 1.0.0  (CLI)  -  Antarmuka grafis (UI) menyusul
 Repo    : https://github.com/bagusdewidn-blip/Rapikan-file
--------------------------------------------------------------------------------
 MIT License

 Copyright (c) 2026 bagusdewidn-blip

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
================================================================================

 APA YANG DILAKUKAN
   1. Duplikat    : file dengan isi identik (dicek SHA-256) -> satu salinan disimpan
   2. Model AI    : file .gguf yang sudah ada di folder model Ollama (blobs)
   3. Arsip       : .zip/.rar/.7z yang sudah diekstrak ke folder bernama sama
   4. Installer   : .exe/.msi/.msix di folder Downloads yang lebih tua dari N hari
   5. Cache       : %TEMP% lama, CrashDumps, cache npm & pip
   6. Rapikan     : file lepas dipindah ke folder per jenis (Dokumen, Gambar, ...)

 KEAMANAN
   - Default = UJI COBA. Tidak ada yang diubah sampai Anda menambahkan -Jalankan.
   - Yang dibuang masuk RECYCLE BIN (bisa dikembalikan), kecuali isi %TEMP%.
   - File sensitif (.key .pem .pub .ppk .kdbx .env dll) TIDAK pernah disentuh.
   - Folder milik aplikasi tidak diubah; hanya file lepas di folder yang dipindai.
   - Setiap run menulis log ke folder tujuan.

 CARA PAKAI (PowerShell biasa, tanpa Administrator)
   powershell -ExecutionPolicy Bypass -File .\rapikan-disk.ps1
   powershell -ExecutionPolicy Bypass -File .\rapikan-disk.ps1 -Jalankan

 PARAMETER
   -Jalankan          Eksekusi sungguhan (tanpa ini hanya uji coba)
   -Folder <path[]>   Folder yang dipindai (default: Downloads, Documents, Desktop)
   -Tujuan <path>     Folder hasil rapikan (default: <home>\Berkas Rapi)
   -HariInstaller <n> Umur minimal installer yang dibuang (default 7 hari)
   -HariTemp <n>      Umur minimal isi %TEMP% yang dihapus (default 2 hari)
   -TanpaRapikan      Lewati tahap memindah file
   -TanpaInstaller    Jangan buang installer
   -TanpaCache        Jangan bersihkan cache
#>
[CmdletBinding()]
param(
  [switch]$Jalankan,
  [string[]]$Folder,
  [string]$Tujuan,
  [int]$HariInstaller = 7,
  [int]$HariTemp = 2,
  [switch]$TanpaRapikan,
  [switch]$TanpaInstaller,
  [switch]$TanpaCache
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName Microsoft.VisualBasic

$Home_ = [Environment]::GetFolderPath('UserProfile')
$Downloads = Join-Path $Home_ 'Downloads'
if (-not $Folder) {
  $Folder = @($Downloads, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop')) |
            Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}
if (-not $Tujuan) { $Tujuan = Join-Path $Home_ 'Berkas Rapi' }

$Sensitif = '.key','.pem','.pub','.ppk','.kdbx','.env','.p12','.pfx','.crt','.cer','.asc','.gpg'
$Abaikan  = '.ini','.lnk','.url','.sys','.tmp','.part','.crdownload'
$Jenis = [ordered]@{
  'Dokumen'       = '.doc','.docx','.odt','.rtf','.pdf','.txt','.md','.xls','.xlsx','.ods','.csv','.ppt','.pptx','.odp'
  'Gambar'        = '.png','.jpg','.jpeg','.webp','.avif','.gif','.bmp','.svg','.heic','.tif','.tiff'
  'Video & Audio' = '.mp4','.mkv','.mov','.avi','.webm','.mp3','.m4a','.wav','.ogg','.flac','.opus'
  'Desain'        = '.psd','.af','.afdesign','.afphoto','.ai','.cdr','.eps','.fig','.xcf'
  'Arsip'         = '.zip','.rar','.7z','.tar','.gz','.iso'
  'Web'           = '.html','.htm','.mhtml'
  'Kode'          = '.py','.js','.ts','.json','.yml','.yaml','.ps1','.sh','.bat','.sql','.php','.css','.xml'
  'Model AI'      = '.gguf','.safetensors','.bin','.onnx'
  'Installer'     = '.exe','.msi','.msix','.msixbundle','.appx'
}

$Tanggal = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $Tujuan ("rapikan-log-{0}{1}.txt" -f $Tanggal, $(if ($Jalankan) { '' } else { '-ujicoba' }))
New-Item -ItemType Directory -Path $Tujuan -Force | Out-Null
$script:Hemat = [int64]0
$script:JmlBuang = 0
$script:JmlPindah = 0
$script:Sudah = @{}   # path yang sudah diproses

function Tulis([string]$teks, [string]$warna = 'Gray') {
  Write-Host $teks -ForegroundColor $warna
  Add-Content -LiteralPath $LogFile -Value $teks -Encoding UTF8
}
function MB([int64]$b) { '{0,9:N0} MB' -f ($b / 1MB) }
function Ukuran($p) {
  $i = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  if (-not $i) { return 0 }
  if ($i.PSIsContainer) { [int64](Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum }
  else { [int64]$i.Length }
}
function Aman($f) { -not ($f.Extension.ToLower() -in $Sensitif) }

function Buang($p, $alasan) {
  if ($script:Sudah[$p] -or -not (Test-Path -LiteralPath $p)) { return }
  $script:Sudah[$p] = $true
  $sz = Ukuran $p
  $script:Hemat += $sz; $script:JmlBuang++
  Tulis ("[BUANG]  {0}  {1}  ({2})" -f (MB $sz), $p, $alasan)
  if ($Jalankan) {
    try {
      if ((Get-Item -LiteralPath $p -Force).PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
      } else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
      }
    } catch { Tulis "   ! gagal: $($_.Exception.Message)" 'Red' }
  }
}

function Pindah($p, $folderTujuan) {
  if ($script:Sudah[$p] -or -not (Test-Path -LiteralPath $p)) { return }
  $script:Sudah[$p] = $true
  $nama = Split-Path $p -Leaf
  $dst = Join-Path $folderTujuan $nama
  $n = 2
  while (Test-Path -LiteralPath $dst) {
    $dst = Join-Path $folderTujuan ('{0}_{1}{2}' -f [IO.Path]::GetFileNameWithoutExtension($nama), $n, [IO.Path]::GetExtension($nama)); $n++
  }
  $script:JmlPindah++
  Tulis "[PINDAH] $p  ->  $dst"
  if ($Jalankan) {
    try {
      New-Item -ItemType Directory -Path $folderTujuan -Force | Out-Null
      if ((Get-Item -LiteralPath $p -Force).PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::MoveDirectory($p, $dst)   # aman lintas drive
      } else {
        Move-Item -LiteralPath $p -Destination $dst -ErrorAction Stop
      }
    } catch { Tulis "   ! gagal: $($_.Exception.Message)" 'Red' }
  }
}

function FileLepas {
  foreach ($d in $Folder) {
    Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -ne $PSCommandPath -and $_.Name -ne 'desktop.ini' -and -not $_.Name.StartsWith('~$') -and (Aman $_) -and -not $script:Sudah[$_.FullName] }
  }
}

# ------------------------------------------------------------------------------
Tulis ('=' * 70) 'Cyan'
Tulis ("rapikan-disk 1.0.0  |  {0}  |  {1}" -f (Get-Date), $(if ($Jalankan) { 'MODE JALANKAN' } else { 'MODE UJI COBA (tidak ada yang diubah)' })) 'Cyan'
Tulis ("Folder dipindai : {0}" -f ($Folder -join '; ')) 'Cyan'
Tulis ("Folder tujuan   : {0}" -f $Tujuan) 'Cyan'
Tulis ('=' * 70) 'Cyan'

# 1. DUPLIKAT ------------------------------------------------------------------
Tulis "`n--- 1. File duplikat (isi identik) ---" 'Green'
$kelompok = FileLepas | Where-Object { $_.Length -gt 0 } | Group-Object Length | Where-Object { $_.Count -gt 1 }
foreach ($g in $kelompok) {
  $perHash = $g.Group | ForEach-Object {
    [pscustomobject]@{ F = $_; H = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash }
  } | Where-Object { $_.H } | Group-Object H | Where-Object { $_.Count -gt 1 }
  foreach ($h in $perHash) {
    # Simpan: nama tanpa akhiran "(1)", lalu yang paling lama dibuat
    $urut = $h.Group.F | Sort-Object @{ E = { $_.BaseName -match '\(\d+\)\s*$' } }, CreationTime
    $simpan = $urut[0]
    $urut | Select-Object -Skip 1 | ForEach-Object { Buang $_.FullName "sama dengan $($simpan.Name)" }
  }
}

# 2. MODEL AI GANDA (Ollama) ---------------------------------------------------
Tulis "`n--- 2. Model AI yang sudah ada di Ollama ---" 'Green'
$ollama = if ($env:OLLAMA_MODELS) { $env:OLLAMA_MODELS } else { Join-Path $Home_ '.ollama\models' }
$blobDir = Join-Path $ollama 'blobs'
if (Test-Path -LiteralPath $blobDir) {
  $blobs = Get-ChildItem -LiteralPath $blobDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100MB }
  $cari = @($Folder) + @($ollama)
  foreach ($d in $cari) {
    Get-ChildItem -LiteralPath $d -File -Filter *.gguf -ErrorAction SilentlyContinue | ForEach-Object {
      $g = $_
      $calon = $blobs | Where-Object { $_.Length -eq $g.Length }
      foreach ($b in $calon) {
        $hb = ($b.Name -replace '^sha256-', '').ToUpper()
        if ((Get-FileHash -LiteralPath $g.FullName -Algorithm SHA256).Hash -eq $hb) { Buang $g.FullName 'sudah ada di Ollama blobs'; break }
      }
    }
  }
} else { Tulis "(folder Ollama tidak ditemukan, dilewati)" }

# 3. ARSIP YANG SUDAH DIEKSTRAK -----------------------------------------------
Tulis "`n--- 3. Arsip yang sudah diekstrak ---" 'Green'
FileLepas | Where-Object { $_.Extension.ToLower() -in '.zip','.rar','.7z' } | ForEach-Object {
  $folderEkstrak = Join-Path $_.DirectoryName $_.BaseName
  if ((Test-Path -LiteralPath $folderEkstrak -PathType Container) -and (Get-ChildItem -LiteralPath $folderEkstrak -Force | Select-Object -First 1)) {
    Buang $_.FullName "sudah diekstrak ke folder $($_.BaseName)"
  }
}

# 4. INSTALLER LAMA ------------------------------------------------------------
Tulis "`n--- 4. Installer lama di Downloads ---" 'Green'
if ($TanpaInstaller) { Tulis '(dilewati)' }
else {
  $batasI = (Get-Date).AddDays(-$HariInstaller)
  FileLepas | Where-Object {
    $_.DirectoryName -eq $Downloads -and $_.Extension.ToLower() -in $Jenis['Installer'] -and $_.LastWriteTime -lt $batasI
  } | ForEach-Object { Buang $_.FullName "installer > $HariInstaller hari" }
}

# 5. CACHE ---------------------------------------------------------------------
Tulis "`n--- 5. Cache & file sementara ---" 'Green'
if ($TanpaCache) { Tulis '(dilewati)' }
else {
  $batasT = (Get-Date).AddDays(-$HariTemp)
  $tmp = Get-ChildItem -LiteralPath $env:TEMP -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $batasT }
  $tmpSz = [int64]0; foreach ($t in $tmp) { $tmpSz += Ukuran $t.FullName }
  $script:Hemat += $tmpSz
  Tulis ("[HAPUS]  {0}  isi %TEMP% lebih tua dari {1} hari ({2} item)" -f (MB $tmpSz), $HariTemp, @($tmp).Count)
  if ($Jalankan) { $tmp | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
  $local = [Environment]::GetFolderPath('LocalApplicationData')
  foreach ($c in (Join-Path $local 'CrashDumps'), (Join-Path $local 'npm-cache\_cacache'), (Join-Path $local 'pip\cache')) {
    if (Test-Path -LiteralPath $c) { Buang $c 'cache, dibuat ulang otomatis' }
  }
}

# 6. RAPIKAN -------------------------------------------------------------------
Tulis "`n--- 6. Rapikan file lepas ke $Tujuan ---" 'Green'
if ($TanpaRapikan) { Tulis '(dilewati)' }
else {
  FileLepas | Where-Object { $_.Extension.ToLower() -notin $Abaikan -and $_.DirectoryName -ne $Tujuan } | ForEach-Object {
    $f = $_; $ext = $f.Extension.ToLower(); $kat = 'Lainnya'
    foreach ($k in $Jenis.Keys) { if ($ext -in $Jenis[$k]) { $kat = $k; break } }
    if ($f.Name -like 'WhatsApp*') { $kat = 'WhatsApp' }
    elseif ($kat -eq 'Gambar' -and $f.Name -match '^(IMG|DSC|ASP|ASR|PXL|DCIM|P\d{7})[_-]?\d') { $kat = 'Foto' }
    elseif ($kat -eq 'Gambar' -and $f.Name -match '(?i)^(screenshot|screen shot|tangkapan layar)') { $kat = 'Screenshot' }
    Pindah $f.FullName (Join-Path $Tujuan $kat)
  }
}

# RINGKASAN --------------------------------------------------------------------
Tulis ("`n" + ('=' * 70)) 'Yellow'
Tulis ("Dibuang : {0} item   Dipindah : {1} item" -f $script:JmlBuang, $script:JmlPindah) 'Yellow'
Tulis ("Perkiraan ruang dibebaskan : {0:N2} GB" -f ($script:Hemat / 1GB)) 'Yellow'
if ($Jalankan) { Tulis "Selesai. Periksa Recycle Bin, lalu kosongkan agar ruang benar-benar lega." 'Yellow' }
else           { Tulis "Ini hanya UJI COBA. Jalankan ulang dengan -Jalankan untuk eksekusi." 'Yellow' }
Tulis "Log: $LogFile" 'Yellow'
