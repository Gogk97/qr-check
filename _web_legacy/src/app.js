/**
 * Main Application Logic
 * UI State, Event Handlers, Filtering, and Batch Actions
 */

document.addEventListener('DOMContentLoaded', () => {
  const detector = new QRDetectorEngine();

  // State
  let scannedItems = [];
  let currentFilter = 'qris'; // 'all', 'qris', 'qr', 'non-qr'
  let isScanning = false;

  // DOM Elements
  const fileInput = document.getElementById('fileInput');
  const cameraInput = document.getElementById('cameraInput');
  const dropZone = document.getElementById('dropZone');
  const galleryGrid = document.getElementById('galleryGrid');
  const emptyState = document.getElementById('emptyState');
  const scanningOverlay = document.getElementById('scanningOverlay');
  const progressBar = document.getElementById('progressBar');
  const progressText = document.getElementById('progressText');
  const progressCount = document.getElementById('progressCount');

  // Stats Elements
  const statAll = document.getElementById('statAll');
  const statQRIS = document.getElementById('statQRIS');
  const statQR = document.getElementById('statQR');
  const statNonQR = document.getElementById('statNonQR');

  // Filter Buttons
  const filterButtons = document.querySelectorAll('[data-filter]');

  // Action Buttons
  const btnSelectAll = document.getElementById('btnSelectAll');
  const btnDeselectAll = document.getElementById('btnDeselectAll');
  const btnDownloadZip = document.getElementById('btnDownloadZip');
  const btnClearAll = document.getElementById('btnClearAll');

  // Modal Elements
  const detailModal = document.getElementById('detailModal');
  const modalClose = document.getElementById('modalClose');
  const modalContent = document.getElementById('modalContent');

  // Initialize Lucide Icons
  if (window.lucide) {
    window.lucide.createIcons();
  }

  // File Selection Triggers
  fileInput.addEventListener('change', (e) => handleFiles(e.target.files));
  if (cameraInput) {
    cameraInput.addEventListener('change', (e) => handleFiles(e.target.files));
  }

  // Drag and Drop
  dropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropZone.classList.add('border-indigo-500', 'bg-indigo-500/10');
  });

  dropZone.addEventListener('dragleave', (e) => {
    e.preventDefault();
    dropZone.classList.remove('border-indigo-500', 'bg-indigo-500/10');
  });

  dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.classList.remove('border-indigo-500', 'bg-indigo-500/10');
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0) {
      handleFiles(e.dataTransfer.files);
    }
  });

  // Filter Switcher
  filterButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      filterButtons.forEach(b => {
        b.classList.remove('bg-indigo-600', 'text-white', 'shadow-md');
        b.classList.add('bg-slate-800/80', 'text-slate-300', 'hover:bg-slate-700/80');
      });
      btn.classList.add('bg-indigo-600', 'text-white', 'shadow-md');
      btn.classList.remove('bg-slate-800/80', 'text-slate-300', 'hover:bg-slate-700/80');

      currentFilter = btn.dataset.filter;
      renderGallery();
    });
  });

  // Handle Files Processing
  async function handleFiles(fileList) {
    if (!fileList || fileList.length === 0) return;
    if (isScanning) return;

    isScanning = true;
    showScanningProgress(0, fileList.length);

    try {
      const results = await detector.scanBatch(fileList, (done, total, current) => {
        showScanningProgress(done, total, current.fileName);
      });

      // Simpan hasil ke state
      results.forEach(res => {
        res.id = 'img_' + Math.random().toString(36).substr(2, 9);
        res.selected = res.isQRIS; // Otomatis tandai checked jika foto mengandung QRIS
        scannedItems.unshift(res);
      });

      // Update counters
      updateStats();

      // Set default filter: jika ada QRIS yang terdeteksi, aktifkan tab QRIS
      const hasQRIS = scannedItems.some(i => i.isQRIS);
      if (hasQRIS) {
        setFilterTab('qris');
      } else {
        setFilterTab('all');
      }

      renderGallery();
    } catch (err) {
      console.error('Batch scanning error:', err);
      showToast('Gagal memindai beberapa gambar: ' + err.message, 'error');
    } finally {
      isScanning = false;
      hideScanningProgress();
      fileInput.value = '';
      if (cameraInput) cameraInput.value = '';
    }
  }

  function showScanningProgress(done, total, currentName = '') {
    scanningOverlay.classList.remove('hidden');
    const percent = Math.round((done / total) * 100) || 0;
    progressBar.style.width = `${percent}%`;
    progressText.innerText = `Memproses foto: ${done} dari ${total} (${percent}%)`;
    if (currentName) {
      progressCount.innerText = `Memindai ${currentName}...`;
    }
  }

  function hideScanningProgress() {
    scanningOverlay.classList.add('hidden');
    progressBar.style.width = '0%';
  }

  function updateStats() {
    const total = scannedItems.length;
    const qrisCount = scannedItems.filter(i => i.isQRIS).length;
    const qrCount = scannedItems.filter(i => i.isQR && !i.isQRIS).length;
    const nonQRCount = scannedItems.filter(i => !i.isQR).length;

    statAll.innerText = total;
    statQRIS.innerText = qrisCount;
    statQR.innerText = qrCount;
    statNonQR.innerText = nonQRCount;
  }

  function setFilterTab(filter) {
    currentFilter = filter;
    filterButtons.forEach(b => {
      if (b.dataset.filter === filter) {
        b.classList.add('bg-indigo-600', 'text-white', 'shadow-md');
        b.classList.remove('bg-slate-800/80', 'text-slate-300', 'hover:bg-slate-700/80');
      } else {
        b.classList.remove('bg-indigo-600', 'text-white', 'shadow-md');
        b.classList.add('bg-slate-800/80', 'text-slate-300', 'hover:bg-slate-700/80');
      }
    });
  }

  function getFilteredItems() {
    switch (currentFilter) {
      case 'qris':
        return scannedItems.filter(i => i.isQRIS);
      case 'qr':
        return scannedItems.filter(i => i.isQR && !i.isQRIS);
      case 'non-qr':
        return scannedItems.filter(i => !i.isQR);
      case 'all':
      default:
        return scannedItems;
    }
  }

  function renderGallery() {
    const items = getFilteredItems();

    if (scannedItems.length === 0) {
      emptyState.classList.remove('hidden');
      galleryGrid.classList.add('hidden');
      return;
    }

    emptyState.classList.add('hidden');
    galleryGrid.classList.remove('hidden');
    galleryGrid.innerHTML = '';

    if (items.length === 0) {
      galleryGrid.innerHTML = `
        <div class="col-span-full py-16 text-center">
          <div class="inline-flex p-4 rounded-full bg-slate-800/80 text-slate-400 mb-3">
            <i data-lucide="search-x" class="w-8 h-8"></i>
          </div>
          <p class="text-base font-medium text-slate-300">Tidak ada gambar untuk kategori "${currentFilter.toUpperCase()}"</p>
          <p class="text-xs text-slate-500 mt-1">Coba ganti filter tab atau tambahkan foto lain dari galeri.</p>
        </div>
      `;
      if (window.lucide) window.lucide.createIcons();
      return;
    }

    items.forEach(item => {
      const card = createCardElement(item);
      galleryGrid.appendChild(card);
    });

    if (window.lucide) window.lucide.createIcons();
  }

  function createCardElement(item) {
    const div = document.createElement('div');
    div.className = `group relative rounded-2xl bg-slate-900/90 border transition-all duration-300 hover:shadow-xl hover:shadow-indigo-500/10 overflow-hidden flex flex-col ${
      item.isQRIS 
        ? 'border-emerald-500/50 shadow-emerald-500/5 hover:border-emerald-400 ring-1 ring-emerald-500/20' 
        : item.isQR 
          ? 'border-amber-500/40 hover:border-amber-400' 
          : 'border-slate-800 hover:border-slate-700 opacity-75'
    }`;

    // Tag badge content
    let badgeHtml = '';
    let detailSummaryHtml = '';

    if (item.isQRIS) {
      badgeHtml = `
        <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-emerald-500/20 text-emerald-400 border border-emerald-500/40 backdrop-blur-md">
          <i data-lucide="badge-check" class="w-3.5 h-3.5"></i>
          QRIS RESMI ${item.isDynamic ? '(Dinamis)' : '(Statis)'}
        </span>
      `;
      detailSummaryHtml = `
        <div class="space-y-1 mt-2">
          <div class="text-sm font-semibold text-white truncate" title="${escapeHtml(item.merchantName)}">
            ${escapeHtml(item.merchantName)}
          </div>
          <div class="flex items-center justify-between text-xs text-slate-400">
            <span class="truncate flex items-center gap-1">
              <i data-lucide="map-pin" class="w-3 h-3 text-slate-500"></i> ${escapeHtml(item.merchantCity || '-')}
            </span>
            ${item.amount ? `<span class="text-emerald-400 font-bold">Rp ${item.amount.toLocaleString('id-ID')}</span>` : '<span class="text-slate-500">Bebas Nominal</span>'}
          </div>
          ${item.nmid ? `<div class="text-[11px] font-mono text-slate-400 truncate">NMID: ${escapeHtml(item.nmid)}</div>` : ''}
        </div>
      `;
    } else if (item.isQR) {
      badgeHtml = `
        <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold bg-amber-500/20 text-amber-300 border border-amber-500/40 backdrop-blur-md">
          <i data-lucide="qr-code" class="w-3.5 h-3.5"></i>
          QR Code Umum
        </span>
      `;
      detailSummaryHtml = `
        <div class="space-y-1 mt-2">
          <div class="text-xs text-slate-300 font-mono line-clamp-2 break-all bg-slate-950/60 p-2 rounded-lg border border-slate-800">
            ${escapeHtml(item.raw)}
          </div>
        </div>
      `;
    } else {
      badgeHtml = `
        <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-slate-800/80 text-slate-400 border border-slate-700 backdrop-blur-md">
          <i data-lucide="image-off" class="w-3.5 h-3.5"></i>
          Bukan QR
        </span>
      `;
      detailSummaryHtml = `
        <div class="mt-2 text-xs text-slate-500 italic">
          Tidak ditemukan kode QR pada gambar ini.
        </div>
      `;
    }

    div.innerHTML = `
      <!-- Thumbnail & Checkbox -->
      <div class="relative w-full aspect-[4/3] bg-slate-950/80 overflow-hidden flex items-center justify-center">
        <img src="${item.previewUrl}" alt="${escapeHtml(item.fileName)}" class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105" loading="lazy">
        
        <!-- Top Overlay: Badges and Select Checkbox -->
        <div class="absolute inset-x-0 top-0 p-3 flex items-start justify-between bg-gradient-to-b from-black/70 via-black/30 to-transparent">
          <div>${badgeHtml}</div>
          <label class="cursor-pointer p-1 rounded-lg bg-black/50 backdrop-blur-md hover:bg-black/70 transition-colors">
            <input type="checkbox" class="card-select-checkbox w-4 h-4 rounded text-indigo-600 focus:ring-indigo-500 focus:ring-offset-0 bg-slate-900 border-slate-700 cursor-pointer" data-id="${item.id}" ${item.selected ? 'checked' : ''}>
          </label>
        </div>
      </div>

      <!-- Card Body -->
      <div class="p-4 flex-1 flex flex-col justify-between">
        <div>
          <div class="flex items-center justify-between text-xs text-slate-400">
            <span class="truncate max-w-[170px]" title="${escapeHtml(item.fileName)}">${escapeHtml(item.fileName)}</span>
            <span>${(item.fileSize / 1024).toFixed(0)} KB</span>
          </div>
          ${detailSummaryHtml}
        </div>

        <!-- Card Actions -->
        <div class="mt-4 pt-3 border-t border-slate-800/80 flex items-center justify-between gap-2">
          ${item.isQR ? `
            <button type="button" class="btn-detail flex-1 py-1.5 px-2.5 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-200 text-xs font-medium flex items-center justify-center gap-1.5 transition-colors" data-id="${item.id}">
              <i data-lucide="info" class="w-3.5 h-3.5"></i> Detail Data
            </button>
          ` : `
            <span class="text-[11px] text-slate-600 py-1.5">Tidak ada payload</span>
          `}
          <button type="button" class="btn-download-single p-1.5 rounded-xl bg-slate-800/80 hover:bg-slate-700 text-slate-300 hover:text-white transition-colors" title="Download Gambar Ini" data-id="${item.id}">
            <i data-lucide="download" class="w-4 h-4"></i>
          </button>
        </div>
      </div>
    `;

    // Event Checkbox
    const checkbox = div.querySelector('.card-select-checkbox');
    checkbox.addEventListener('change', (e) => {
      item.selected = e.target.checked;
    });

    // Event Detail Modal
    const btnDetail = div.querySelector('.btn-detail');
    if (btnDetail) {
      btnDetail.addEventListener('click', () => openDetailModal(item));
    }

    // Event Download Single
    const btnDownload = div.querySelector('.btn-download-single');
    if (btnDownload) {
      btnDownload.addEventListener('click', () => {
        const link = document.createElement('a');
        link.href = item.previewUrl;
        link.download = item.fileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
      });
    }

    return div;
  }

  // Batch Select Actions
  btnSelectAll.addEventListener('click', () => {
    const items = getFilteredItems();
    items.forEach(i => i.selected = true);
    renderGallery();
    showToast(`Dipilih ${items.length} gambar`, 'info');
  });

  btnDeselectAll.addEventListener('click', () => {
    const items = getFilteredItems();
    items.forEach(i => i.selected = false);
    renderGallery();
  });

  // Clear All
  btnClearAll.addEventListener('click', () => {
    if (scannedItems.length === 0) return;
    if (confirm('Bersihkan semua daftar gambar yang sudah dipindai?')) {
      scannedItems.forEach(i => {
        if (i.previewUrl) URL.revokeObjectURL(i.previewUrl);
      });
      scannedItems = [];
      updateStats();
      renderGallery();
      showToast('Daftar gambar dibersihkan', 'info');
    }
  });

  // Batch Download as ZIP
  btnDownloadZip.addEventListener('click', async () => {
    const selected = scannedItems.filter(i => i.selected);
    if (selected.length === 0) {
      showToast('Pilih setidaknya 1 gambar untuk di-download!', 'warning');
      return;
    }

    if (!window.JSZip) {
      showToast('Library kompresi ZIP belum siap', 'error');
      return;
    }

    showToast(`Mempersiapkan ZIP untuk ${selected.length} foto...`, 'info');

    try {
      const zip = new window.JSZip();
      const folder = zip.folder('qris_images');

      // Masukkan manifest data teks / JSON rincian
      const manifestData = selected.map(item => ({
        fileName: item.fileName,
        isQRIS: item.isQRIS,
        isDynamic: item.isDynamic || false,
        merchantName: item.merchantName || null,
        merchantCity: item.merchantCity || null,
        nmid: item.nmid || null,
        amount: item.amount || null,
        rawPayload: item.raw || ''
      }));

      folder.file('hasil_deteksi_qris.json', JSON.stringify(manifestData, null, 2));

      // Tambahkan foto ke ZIP
      for (let i = 0; i < selected.length; i++) {
        const item = selected[i];
        folder.file(item.fileName, item.file);
      }

      const zipBlob = await zip.generateAsync({ type: 'blob' });
      const downloadUrl = URL.createObjectURL(zipBlob);
      const a = document.createElement('a');
      a.href = downloadUrl;
      a.download = `koleksi-qris-${Date.now()}.zip`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(downloadUrl);

      showToast(`Berhasil mengunduh ${selected.length} foto dalam format ZIP!`, 'success');
    } catch (err) {
      console.error('ZIP generation error:', err);
      showToast('Gagal membuat file ZIP: ' + err.message, 'error');
    }
  });

  // Open Detail Modal
  function openDetailModal(item) {
    if (!item) return;

    let contentHtml = '';
    if (item.isQRIS) {
      contentHtml = `
        <div class="space-y-4">
          <div class="flex items-center gap-3 p-3 rounded-2xl bg-emerald-500/10 border border-emerald-500/30">
            <div class="p-2.5 rounded-xl bg-emerald-500/20 text-emerald-400">
              <i data-lucide="shield-check" class="w-6 h-6"></i>
            </div>
            <div>
              <h4 class="text-sm font-bold text-white">QRIS Standar Nasional Valid</h4>
              <p class="text-xs text-emerald-300">Format EMVCo MPM Bank Indonesia & ASPI</p>
            </div>
          </div>

          <!-- Merchant Info Table -->
          <div class="grid grid-cols-2 gap-3 text-xs">
            <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700">
              <span class="text-slate-400 block mb-0.5">Nama Merchant (Tag 59)</span>
              <span class="text-white font-semibold text-sm">${escapeHtml(item.merchantName)}</span>
            </div>
            <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700">
              <span class="text-slate-400 block mb-0.5">Kota (Tag 60)</span>
              <span class="text-white font-semibold text-sm">${escapeHtml(item.merchantCity)}</span>
            </div>
            <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700">
              <span class="text-slate-400 block mb-0.5">Tipe Pembayaran</span>
              <span class="text-emerald-400 font-semibold">${item.isDynamic ? 'QRIS Dinamis' : 'QRIS Statis'}</span>
            </div>
            <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700">
              <span class="text-slate-400 block mb-0.5">Nominal Transaksi</span>
              <span class="text-white font-semibold">${item.amount ? 'Rp ' + item.amount.toLocaleString('id-ID') : 'Bebas Diinput Pembeli'}</span>
            </div>
            <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700 col-span-2">
              <span class="text-slate-400 block mb-0.5">NMID / ID Merchant (Tag 51/26)</span>
              <span class="font-mono text-indigo-300 select-all">${escapeHtml(item.nmid || '-')}</span>
            </div>
            <div class="bg-slate-800/60 p-3 rounded-xl border border-slate-700 col-span-2">
              <span class="text-slate-400 block mb-0.5">Integritas Data (Checksum CRC16)</span>
              <span class="flex items-center gap-1.5 ${item.isValidCRC ? 'text-emerald-400' : 'text-amber-400'} font-medium">
                <i data-lucide="${item.isValidCRC ? 'check-circle-2' : 'alert-circle'}" class="w-3.5 h-3.5"></i>
                ${item.isValidCRC ? 'Checksum Valid & Asli' : 'Checksum Perlu Verifikasi'}
              </span>
            </div>
          </div>

          <!-- Raw String -->
          <div class="space-y-1.5">
            <div class="flex items-center justify-between text-xs">
              <span class="text-slate-400">Raw QR Payload String:</span>
              <button type="button" id="btnCopyRaw" class="text-indigo-400 hover:text-indigo-300 font-medium">Salin Teks</button>
            </div>
            <textarea readonly class="w-full h-24 p-2.5 rounded-xl bg-slate-950 font-mono text-[11px] text-slate-300 border border-slate-800 resize-none select-all">${escapeHtml(item.raw)}</textarea>
          </div>
        </div>
      `;
    } else {
      contentHtml = `
        <div class="space-y-4">
          <div class="flex items-center gap-3 p-3 rounded-2xl bg-amber-500/10 border border-amber-500/30">
            <div class="p-2.5 rounded-xl bg-amber-500/20 text-amber-400">
              <i data-lucide="qr-code" class="w-6 h-6"></i>
            </div>
            <div>
              <h4 class="text-sm font-bold text-white">QR Code Non-QRIS</h4>
              <p class="text-xs text-amber-300">Tipe data: ${escapeHtml(item.type.toUpperCase())}</p>
            </div>
          </div>

          <!-- Raw String -->
          <div class="space-y-1.5">
            <div class="flex items-center justify-between text-xs">
              <span class="text-slate-400">Isi QR Code:</span>
              <button type="button" id="btnCopyRaw" class="text-indigo-400 hover:text-indigo-300 font-medium">Salin Teks</button>
            </div>
            <textarea readonly class="w-full h-28 p-2.5 rounded-xl bg-slate-950 font-mono text-xs text-slate-300 border border-slate-800 resize-none select-all">${escapeHtml(item.raw)}</textarea>
          </div>
        </div>
      `;
    }

    modalContent.innerHTML = contentHtml;
    detailModal.classList.remove('hidden');

    if (window.lucide) window.lucide.createIcons();

    const btnCopy = document.getElementById('btnCopyRaw');
    if (btnCopy) {
      btnCopy.addEventListener('click', () => {
        navigator.clipboard.writeText(item.raw);
        showToast('Payload berhasil disalin ke clipboard!', 'success');
      });
    }
  }

  modalClose.addEventListener('click', () => {
    detailModal.classList.add('hidden');
  });

  detailModal.addEventListener('click', (e) => {
    if (e.target === detailModal) {
      detailModal.classList.add('hidden');
    }
  });

  // Toast Notification Helper
  function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    const colorClass = 
      type === 'success' ? 'bg-emerald-600 text-white' :
      type === 'error' ? 'bg-rose-600 text-white' :
      type === 'warning' ? 'bg-amber-600 text-white' :
      'bg-indigo-600 text-white';

    toast.className = `fixed bottom-6 right-6 z-50 px-4 py-2.5 rounded-xl shadow-2xl flex items-center gap-2 text-sm font-medium transition-all duration-300 transform translate-y-4 opacity-0 ${colorClass}`;
    toast.innerHTML = `
      <i data-lucide="${type === 'success' ? 'check' : type === 'error' ? 'alert-triangle' : 'info'}" class="w-4 h-4"></i>
      <span>${escapeHtml(message)}</span>
    `;

    document.body.appendChild(toast);
    if (window.lucide) window.lucide.createIcons();

    setTimeout(() => {
      toast.classList.remove('translate-y-4', 'opacity-0');
    }, 10);

    setTimeout(() => {
      toast.classList.add('translate-y-4', 'opacity-0');
      setTimeout(() => toast.remove(), 300);
    }, 3000);
  }

  function escapeHtml(string) {
    if (!string) return '';
    return String(string)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
});
