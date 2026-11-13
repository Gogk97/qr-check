# Panduan Setup Backend Supabase untuk QR-Check

Dokumen ini berisi panduan setup backend Supabase untuk aplikasi **qr-check** (Autentikasi Google/Guest, Kuota Hapus Foto Atomik, Transaksi QRIS Manual, dan Bucket Bukti Transfer).

---

## 1. Buat Project Baru di Supabase (2-3 Menit)

1. Buka [https://supabase.com](https://supabase.com) dan login/daftar (bisa pakai akun GitHub).
2. Klik tombol **New project**.
3. Isi form:
   - **Name**: `qr-check-backend` (atau nama lain yang diinginkan).
   - **Database Password**: Buat password kuat dan simpan di password manager Anda.
   - **Region**: Pilih **Singapore (ap-southeast-1)** agar latensi ke Indonesia sangat rendah (< 30ms).
   - **Pricing Plan**: **Free** (cukup untuk testing hingga ribuan user).
4. Klik **Create new project** dan tunggu proses provisioning (~1-2 menit).

---

## 2. Dapatkan Kredensial API

Setelah project selesai dibuat:
1. Buka menu **Project Settings** (ikon gerigi di sidebar kiri bawah) > **API**.
2. Salin nilai berikut:
   - **Project URL** (contoh: `https://xyzcompany.supabase.co`)
   - **anon / public key** (token panjang berawalan `eyJ...`)

> Simpan kedua nilai ini karena akan dimasukkan ke konfigurasi Flutter.

---

## 3. Aktifkan Autentikasi (Google & Anonymous / Guest)

Buka menu **Authentication** > **Providers** di sidebar Supabase:

### A. Anonymous Sign-In (Untuk Pengguna Tamu / Guest)
1. Cari provider **Anonymous**.
2. Aktifkan toggle **Enable Anonymous Sign-ins**.
3. Klik **Save**.
*(Dengan fitur ini, pengguna guest memiliki JWT resmi dan User ID unik di server tanpa butuh device ID buatan sendiri).*

### B. Google Sign-In
1. Cari provider **Google**.
2. Aktifkan toggle **Enable Google provider**.
3. Masukkan **Client ID** dan **Client Secret** dari Google Cloud Console Anda.
4. Klik **Save**.

---

## 4. Eksekusi Skema Database & Keamanan (RLS)

1. Buka menu **SQL Editor** di sidebar Supabase.
2. Klik **New query**.
3. Buka file [`supabase/schema.sql`](./schema.sql) di repo ini, salin seluruh kodenya, lalu tempelkan ke SQL Editor.
4. Klik tombol **Run** (atau tekan `Ctrl+Enter` / `Cmd+Enter`).
5. Pastikan muncul pesan sukses: `Success. No rows returned`.

### Apa yang telah dibuat oleh `schema.sql`:
- **Tabel `profiles`**: Menyimpan profil, kuota (`remaining_quota`), status `is_pro`.
- **Tabel `quota_ledger`**: Catatan riwayat mutasi kuota (append-only, tidak bisa di-tamper).
- **Tabel `payments`**: Data transaksi pembayaran QRIS Rp15.000 dengan status PENDING/APPROVED/REJECTED.
- **Tabel `ad_reward_events`**: Verifikasi reward iklan anti-replay.
- **Trigger `on_auth_user_created`**: Otomatis memberi kuota 10 (Google) atau 5 (Guest) saat pertama daftar.
- **Fungsi RPC `consume_quota`**: Memotong kuota secara atomik (pencegahan race-condition).
- **Fungsi RPC `submit_payment`**: Mengirim pengajuan pembayaran dan mengaitkan bukti upload.
- **Fungsi RPC `approve_payment` & `reject_payment`**: Khusus admin untuk verifikasi pembayaran manual.
- **Storage Bucket `payment-proofs`**: Private bucket untuk upload foto bukti transfer (maks 5MB, format JPG/PNG).

---

## 5. Menetapkan Akun Anda Sebagai Admin (Untuk Approve Pembayaran)

Setelah Anda login pertama kali ke aplikasi atau membuat akun via Supabase Auth dengan email Anda, jadikan akun Anda sebagai admin dengan menjalankan query ini di **SQL Editor**:

```sql
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role": "admin"}'::jsonb
WHERE email = 'email-anda@gmail.com';
```

*(Catatan: `raw_app_meta_data` hanya bisa diubah melalui SQL Editor / service role Supabase dan tidak bisa dipalsukan oleh client).*

---

## 6. Cara Melakukan Verifikasi Pembayaran Manual (Admin)

Ketika ada pengguna yang mentransfer dan mengunggah bukti pembayaran QRIS:

### Opsi A: Lewat Supabase Studio (Table Editor)
1. Buka menu **Table Editor** > tabel `payments`.
2. Klik baris pembayaran yang berstatus `PENDING`.
3. Buka file bukti transfer di menu **Storage** > `payment-proofs` > buka folder ID user.
4. Jika valid, jalankan di **SQL Editor**:
   ```sql
   SELECT public.approve_payment('ID_PEMBAYARAN_DISINI');
   ```
   *Secara otomatis status pembayaran berubah menjadi `APPROVED` dan profil pengguna tersebut langsung menjadi `is_pro = true` (Unlimited Quota).*

### Opsi B: Tolak Pembayaran jika Tidak Valid
```sql
SELECT public.reject_payment('ID_PEMBAYARAN_DISINI', 'Nominal tidak sesuai / bukti transfer buram');
```

---

## 7. Langkah Selanjutnya (Integrasi ke Flutter)

Tambahkan dependency ke `pubspec.yaml` aplikasi Flutter:
```yaml
dependencies:
  supabase_flutter: ^2.8.0
```

Dan inisialisasi di `lib/main.dart`:
```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL',
  anonKey: 'YOUR_SUPABASE_ANON_KEY',
);
```
