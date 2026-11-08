# Rapikan-file (rapikan-disk.ps1)

Bersihkan dan rapikan penyimpanan Windows dengan **satu file PowerShell**. Tidak perlu install, tidak perlu Administrator.

> **Status:** versi CLI (baris perintah). **Antarmuka grafis (UI) menyusul.**

## Fitur

| Tahap | Yang dilakukan |
|---|---|
| 1. Duplikat | File dengan isi identik (dicek SHA-256) — satu salinan disimpan, sisanya dibuang |
| 2. Model AI | File `.gguf` yang sudah tersimpan di folder model Ollama (`blobs`) |
| 3. Arsip | `.zip` / `.rar` / `.7z` yang sudah diekstrak ke folder bernama sama |
| 4. Installer | `.exe` / `.msi` / `.msix` di Downloads yang lebih tua dari 7 hari |
| 5. Cache | `%TEMP%` lama, CrashDumps, cache npm & pip |
| 6. Rapikan | File lepas dipindah ke folder per jenis: Dokumen, Gambar, Foto, WhatsApp, Video & Audio, Desain, Arsip, Web, Kode, Model AI, Installer, Lainnya |

## Aman secara default

- **Uji coba dulu.** Tanpa `-Jalankan`, skrip hanya menampilkan rencana, tidak ada yang diubah.
- **Recycle Bin.** Semua yang dibuang bisa dikembalikan (kecuali isi `%TEMP%`).
- **File sensitif tidak disentuh:** `.key` `.pem` `.pub` `.ppk` `.kdbx` `.env` `.pfx` dll.
- **Folder milik aplikasi tidak diubah** — hanya file lepas di folder yang dipindai.
- **Log** setiap run disimpan di folder tujuan.

## Cara pakai

1. Unduh [`rapikan-disk.ps1`](rapikan-disk.ps1).
2. Buka PowerShell di folder tempat file itu berada, lalu:

```powershell
# Uji coba (tidak mengubah apa pun)
powershell -ExecutionPolicy Bypass -File .\rapikan-disk.ps1

# Eksekusi sungguhan
powershell -ExecutionPolicy Bypass -File .\rapikan-disk.ps1 -Jalankan
```

3. Periksa Recycle Bin, lalu kosongkan agar ruang benar-benar lega.

### Parameter

| Parameter | Fungsi | Default |
|---|---|---|
| `-Jalankan` | Eksekusi sungguhan | uji coba |
| `-Folder` | Folder yang dipindai | Downloads, Documents, Desktop |
| `-Tujuan` | Folder hasil rapikan | `%USERPROFILE%\Berkas Rapi` |
| `-HariInstaller` | Umur minimal installer yang dibuang | 7 |
| `-HariTemp` | Umur minimal isi `%TEMP%` yang dihapus | 2 |
| `-TanpaRapikan` | Lewati tahap memindah file | – |
| `-TanpaInstaller` | Jangan buang installer | – |
| `-TanpaCache` | Jangan bersihkan cache | – |

Contoh: pindai dua drive data dan simpan hasilnya di drive D:

```powershell
.\rapikan-disk.ps1 -Folder "D:\Downloads","C:\Users\Saya\Downloads" -Tujuan "D:\berkas" -Jalankan
```

## Rencana

- [ ] Antarmuka grafis (UI) — pilih folder, centang item, lihat ukuran sebelum membuang
- [ ] Laporan folder terbesar per drive
- [ ] Jadwal otomatis (Task Scheduler)

## Lisensi

[MIT](LICENSE) © 2026 bagusdewidn-blip. Teks lisensi juga tertanam di kepala file `rapikan-disk.ps1`, jadi tetap ikut walau file disebar sendirian.

Skrip ini disediakan apa adanya. Selalu jalankan uji coba dan periksa daftarnya sebelum `-Jalankan`.
