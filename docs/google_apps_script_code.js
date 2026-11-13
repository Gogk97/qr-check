/**
 * ============================================================================
 * GOOGLE APPS SCRIPT - MULTI-SPREADSHEET BACKEND FOR QRIS DETECTOR
 * ============================================================================
 * 
 * Target Google Spreadsheets resmi:
 * 1. Data Transaksi:
 *    https://docs.google.com/spreadsheets/d/19V_tDZ6Gi9n7JP3vqhkNWMdrZIwLpffx8qIdeqaMwMw
 * 
 * 2. Data User Login with Google:
 *    https://docs.google.com/spreadsheets/d/1FRAANDXXns0nx9Wi6XuWe3qmbNFMy3fdMrEVCi9eOq8
 * 
 * 3. Data User Guest:
 *    https://docs.google.com/spreadsheets/d/126GXtgjq68XN5IpypgHGmpUzemwossAyr4IOGCdLUl8
 * 
 * ----------------------------------------------------------------------------
 * ATURAN KEAMANAN & INTEGRITAS DATA (STRICT POLICY):
 * 1. HANYA MENAMBAH (append) dan MEMPERBARUI (update) data.
 * 2. DILARANG KERAS MENGHAPUS DATA (Zero-Deletion Guarantee: tidak ada deleteRow/clear).
 * 3. Foto bukti pembayaran otomatis diupload ke Google Drive folder milik Anda.
 * ----------------------------------------------------------------------------
 * 
 * PANDUAN DEPLOYMENT (3 MENIT):
 * 1. Buka https://script.google.com/home/start atau buka menu Ekstensi > Apps Script
 *    pada salah satu spreadsheet di atas.
 * 2. Hapus seluruh isi editor bawaan, lalu paste seluruh skrip ini.
 * 3. Klik tombol Simpan (Save) 💾.
 * 4. Klik tombol "Terapkan" (Deploy) di kanan atas > pilih "Penerapan baru" (New deployment).
 * 5. Pilih jenis: "Aplikasi web" (Web app).
 * 6. Setelan:
 *    - Deskripsi : QRIS Detector Multi-Sheet Webhook
 *    - Jalankan sebagai (Execute as) : Saya (Me / email Google Anda)
 *    - Yang memiliki akses (Who has access) : Siapa saja (Anyone) <--- WAJIB
 * 7. Klik "Terapkan" (Deploy) & berikan izin akses Google ("Izinkan").
 * 8. Salin URL Aplikasi Web (https://script.google.com/macros/s/.../exec).
 * 9. Tempelkan URL tersebut ke aplikasi QRIS Detector (ikon ⚙️ di pojok kanan atas Layar Pembayaran).
 * ============================================================================
 */

// Target Spreadsheet IDs
var CONFIG = {
  SPREADSHEETS: {
    TRANSAKSI: '19V_tDZ6Gi9n7JP3vqhkNWMdrZIwLpffx8qIdeqaMwMw',
    USER_GOOGLE: '1FRAANDXXns0nx9Wi6XuWe3qmbNFMy3fdMrEVCi9eOq8',
    USER_GUEST: '126GXtgjq68XN5IpypgHGmpUzemwossAyr4IOGCdLUl8'
  },
  DRIVE_FOLDER_NAME: 'Bukti Pembayaran QRIS Detector'
};

function doPost(e) {
  var lock = LockService.getScriptLock();
  // Cegah race condition antar user (tunggu hingga 30 detik)
  lock.tryLock(30000);

  try {
    if (!e || !e.postData || !e.postData.contents) {
      return jsonResponse({
        status: 'error',
        message: 'Payload kosong / tidak ada data yang diterima.'
      });
    }

    var data = JSON.parse(e.postData.contents);
    var action = data.action || 'RECORD_PAYMENT';

    // ─────────────────────────────────────────────────────────────
    // 1. ACTION: SINKRONISASI USER (GOOGLE ATAU GUEST)
    // ─────────────────────────────────────────────────────────────
    if (action === 'SYNC_USER') {
      var isGoogle = (data.userType === 'GOOGLE');
      var targetSheetId = isGoogle ? CONFIG.SPREADSHEETS.USER_GOOGLE : CONFIG.SPREADSHEETS.USER_GUEST;
      var sheet = getSheetById(targetSheetId);

      if (isGoogle) {
        initGoogleUserHeaders(sheet);
        upsertGoogleUser(sheet, data);
      } else {
        initGuestUserHeaders(sheet);
        upsertGuestUser(sheet, data);
      }

      return jsonResponse({
        status: 'success',
        message: 'Data user berhasil disinkronisasi ke Google Sheet (' + (isGoogle ? 'Google' : 'Guest') + ').',
        userId: data.userId
      });
    }

    // ─────────────────────────────────────────────────────────────
    // 2. ACTION: UPDATE KUOTA PENGGUNA
    // ─────────────────────────────────────────────────────────────
    if (action === 'UPDATE_QUOTA') {
      var isGoogleUser = (data.userType === 'GOOGLE');
      var sheetId = isGoogleUser ? CONFIG.SPREADSHEETS.USER_GOOGLE : CONFIG.SPREADSHEETS.USER_GUEST;
      var targetSheet = getSheetById(sheetId);

      updateUserQuota(targetSheet, data.userId, data.remainingQuota);

      return jsonResponse({
        status: 'success',
        message: 'Kuota user ' + data.userId + ' berhasil diperbarui ke ' + data.remainingQuota
      });
    }

    // ─────────────────────────────────────────────────────────────
    // 3. ACTION: CATAT TRANSAKSI PEMBAYARAN & UPLOAD BUKTI KE DRIVE
    // ─────────────────────────────────────────────────────────────
    var txSheet = getSheetById(CONFIG.SPREADSHEETS.TRANSAKSI);
    initTransactionHeaders(txSheet);

    var proofDriveUrl = '-';

    // Upload bukti transfer base64 ke Google Drive jika ada
    if (data.imageBase64 && data.imageBase64.length > 50) {
      var folders = DriveApp.getFoldersByName(CONFIG.DRIVE_FOLDER_NAME);
      var folder = folders.hasNext() ? folders.next() : DriveApp.createFolder(CONFIG.DRIVE_FOLDER_NAME);

      var decodedBytes = Utilities.base64Decode(data.imageBase64);
      var fileName = (data.orderId || ('ORD-' + Date.now())) + '_' + (data.senderBank || 'transfer') + '.jpg';
      var blob = Utilities.newBlob(decodedBytes, data.mimeType || 'image/jpeg', fileName);
      var file = folder.createFile(blob);

      // Atur hak akses agar link Drive dapat langsung dibuka oleh pemilik sheet
      file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
      proofDriveUrl = file.getUrl();
    }

    // Tambah baris transaksi baru (HANYA APPEND / NO DELETION)
    txSheet.appendRow([
      new Date(),
      data.orderId || ('ORD-' + Date.now()),
      data.userId || '-',
      data.userName || '-',
      data.userEmail || '-',
      data.senderBank || '-',
      data.amount || 15000,
      data.status || 'PENDING',
      proofDriveUrl,
      data.notes || '-'
    ]);

    return jsonResponse({
      status: 'success',
      message: 'Transaksi berhasil dicatat ke Data Transaksi & Bukti tersimpan di Google Drive!',
      orderId: data.orderId,
      proofUrl: proofDriveUrl
    });

  } catch (err) {
    return jsonResponse({
      status: 'error',
      message: 'Gagal memproses ke Google Sheets / Drive: ' + err.toString()
    });

  } finally {
    lock.releaseLock();
  }
}

function doGet(e) {
  return jsonResponse({
    status: 'online',
    service: 'QRIS Detector Multi-Sheet Google Cloud Sync',
    timestamp: new Date().toISOString(),
    sheets: CONFIG.SPREADSHEETS
  });
}

// ─────────────────────────────────────────────────────────────────
// HELPER FUNCTIONS & SHEET MANAGERS (STRICT NO-DELETE IMPLEMENTATION)
// ─────────────────────────────────────────────────────────────────

function getSheetById(spreadsheetId) {
  try {
    var ss = SpreadsheetApp.openById(spreadsheetId);
    return ss.getActiveSheet();
  } catch (e) {
    // Fallback jika dijalankan langsung di container spreadsheet aktif
    return SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  }
}

function initTransactionHeaders(sheet) {
  if (sheet.getLastRow() === 0) {
    var headers = [
      'Waktu Submit',
      'Order ID',
      'User ID',
      'Nama User',
      'Email User',
      'Bank / E-Wallet Pengirim',
      'Nominal (IDR)',
      'Status Pembayaran',
      'Link Foto Bukti (Google Drive)',
      'Catatan'
    ];
    sheet.appendRow(headers);
    styleHeaderRange(sheet, headers.length, '#0F172A');
  }
}

function initGoogleUserHeaders(sheet) {
  if (sheet.getLastRow() === 0) {
    var headers = [
      'Waktu Pertama Login',
      'User ID',
      'Nama Akun Google',
      'Email Google',
      'Foto Profil URL',
      'Sisa Kuota Hapus',
      'Status PRO',
      'Perangkat / OS',
      'Terakhir Aktif'
    ];
    sheet.appendRow(headers);
    styleHeaderRange(sheet, headers.length, '#1E3A8A');
  }
}

function initGuestUserHeaders(sheet) {
  if (sheet.getLastRow() === 0) {
    var headers = [
      'Waktu Pertama Login',
      'Guest ID',
      'Nama Tamu',
      'Tipe Akun',
      'Sisa Kuota Hapus',
      'Status PRO',
      'Perangkat / OS',
      'Terakhir Aktif'
    ];
    sheet.appendRow(headers);
    styleHeaderRange(sheet, headers.length, '#065F46');
  }
}

function styleHeaderRange(sheet, colCount, hexColor) {
  var range = sheet.getRange(1, 1, 1, colCount);
  range.setBackground(hexColor);
  range.setFontColor('#FFFFFF');
  range.setFontWeight('bold');
  range.setHorizontalAlignment('center');
  sheet.setFrozenRows(1);
}

// UPDATE OR INSERT (UPSERT) USER GOOGLE (NO DELETION)
function upsertGoogleUser(sheet, data) {
  var lastRow = sheet.getLastRow();
  var userId = data.userId;
  var rowIndex = -1;

  if (lastRow > 1) {
    var userIds = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
    for (var i = 0; i < userIds.length; i++) {
      if (userIds[i][0] == userId) {
        rowIndex = i + 2; // offset header
        break;
      }
    }
  }

  if (rowIndex > 0) {
    // UPDATE baris eksisting (hanya mengubah kuota, pro status, terakhir aktif)
    sheet.getRange(rowIndex, 6).setValue(data.remainingQuota != null ? data.remainingQuota : 10);
    sheet.getRange(rowIndex, 7).setValue(data.isPro ? 'TRUE' : 'FALSE');
    sheet.getRange(rowIndex, 8).setValue(data.devicePlatform || '-');
    sheet.getRange(rowIndex, 9).setValue(new Date());
  } else {
    // APPEND baris baru
    sheet.appendRow([
      new Date(),
      userId,
      data.userName || '-',
      data.userEmail || '-',
      data.avatarUrl || '-',
      data.remainingQuota != null ? data.remainingQuota : 10,
      data.isPro ? 'TRUE' : 'FALSE',
      data.devicePlatform || '-',
      new Date()
    ]);
  }
}

// UPDATE OR INSERT (UPSERT) USER GUEST (NO DELETION)
function upsertGuestUser(sheet, data) {
  var lastRow = sheet.getLastRow();
  var guestId = data.userId;
  var rowIndex = -1;

  if (lastRow > 1) {
    var guestIds = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
    for (var i = 0; i < guestIds.length; i++) {
      if (guestIds[i][0] == guestId) {
        rowIndex = i + 2;
        break;
      }
    }
  }

  if (rowIndex > 0) {
    // UPDATE baris eksisting
    sheet.getRange(rowIndex, 5).setValue(data.remainingQuota != null ? data.remainingQuota : 5);
    sheet.getRange(rowIndex, 6).setValue(data.isPro ? 'TRUE' : 'FALSE');
    sheet.getRange(rowIndex, 7).setValue(data.devicePlatform || '-');
    sheet.getRange(rowIndex, 8).setValue(new Date());
  } else {
    // APPEND baris baru
    sheet.appendRow([
      new Date(),
      guestId,
      data.userName || 'Tamu',
      'GUEST',
      data.remainingQuota != null ? data.remainingQuota : 5,
      data.isPro ? 'TRUE' : 'FALSE',
      data.devicePlatform || '-',
      new Date()
    ]);
  }
}

// UPDATE KUOTA USER TERPILIH (NO DELETION)
function updateUserQuota(sheet, userId, newQuota) {
  var lastRow = sheet.getLastRow();
  if (lastRow <= 1) return;

  var headers = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  var quotaCol = -1;
  var lastActiveCol = -1;

  for (var c = 0; c < headers.length; c++) {
    var h = String(headers[c]).toLowerCase();
    if (h.indexOf('kuota') >= 0) quotaCol = c + 1;
    if (h.indexOf('aktif') >= 0) lastActiveCol = c + 1;
  }

  if (quotaCol === -1) quotaCol = 5;
  if (lastActiveCol === -1) lastActiveCol = headers.length;

  var ids = sheet.getRange(2, 2, lastRow - 1, 1).getValues();
  for (var i = 0; i < ids.length; i++) {
    if (ids[i][0] == userId) {
      var row = i + 2;
      sheet.getRange(row, quotaCol).setValue(newQuota);
      sheet.getRange(row, lastActiveCol).setValue(new Date());
      break;
    }
  }
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
