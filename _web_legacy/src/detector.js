/**
 * QR & QRIS Image Detection Engine
 * Multi-layer scanner: Native BarcodeDetector -> jsQR Canvas Fallback -> Adaptive Preprocessing
 */

class QRDetectorEngine {
  constructor() {
    this.hasBarcodeDetector = typeof window !== 'undefined' && 'BarcodeDetector' in window;
    this.barcodeDetector = null;

    if (this.hasBarcodeDetector) {
      try {
        this.barcodeDetector = new window.BarcodeDetector({ formats: ['qr_code'] });
      } catch (e) {
        console.warn('BarcodeDetector format qr_code not supported, fallback to jsQR', e);
        this.hasBarcodeDetector = false;
      }
    }
  }

  /**
   * Muat gambar dari File ke HTMLImageElement
   */
  loadImage(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => resolve({ img, url });
      img.onerror = (err) => {
        URL.revokeObjectURL(url);
        reject(err);
      };
      img.src = url;
    });
  }

  /**
   * Gambar ke Canvas dengan ukuran teroptimasi (max 1600px)
   */
  getOptimizedCanvas(img) {
    const canvas = document.createElement('canvas');
    let width = img.naturalWidth || img.width;
    let height = img.naturalHeight || img.height;
    const maxDim = 1600;

    if (width > maxDim || height > maxDim) {
      if (width > height) {
        height = Math.round((height * maxDim) / width);
        width = maxDim;
      } else {
        width = Math.round((width * maxDim) / height);
        height = maxDim;
      }
    }

    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, width, height);
    return { canvas, ctx, width, height };
  }

  /**
   * Pindai satu file gambar
   * @param {File} file 
   * @returns {Promise<Object>}
   */
  async scanFile(file) {
    let loaded;
    try {
      loaded = await this.loadImage(file);
    } catch (e) {
      return {
        file,
        fileName: file.name,
        fileSize: file.size,
        success: false,
        error: 'Gagal memuat gambar',
        isQR: false,
        isQRIS: false
      };
    }

    const { img, url } = loaded;
    const { canvas, ctx, width, height } = this.getOptimizedCanvas(img);
    let detectedRaw = null;
    let detectionMethod = 'none';

    // 1. Coba Native BarcodeDetector terlebih dahulu
    if (this.hasBarcodeDetector && this.barcodeDetector) {
      try {
        const barcodes = await this.barcodeDetector.detect(canvas);
        if (barcodes && barcodes.length > 0) {
          detectedRaw = barcodes[0].rawValue;
          detectionMethod = 'native-barcodedetector';
        }
      } catch (err) {
        console.warn('Native BarcodeDetector detect failed, trying jsQR fallback', err);
      }
    }

    // 2. Fallback jsQR jika belum terdeteksi
    if (!detectedRaw && typeof window.jsQR === 'function') {
      try {
        const imageData = ctx.getImageData(0, 0, width, height);
        const code = window.jsQR(imageData.data, width, height, {
          inversionAttempts: 'attemptBoth'
        });
        if (code && code.data) {
          detectedRaw = code.data;
          detectionMethod = 'jsQR';
        }
      } catch (err) {
        console.warn('jsQR scan error', err);
      }
    }

    // 3. Jika masih belum terdeteksi, coba dengan peningkatan kontras sederhana (adaptive)
    if (!detectedRaw && typeof window.jsQR === 'function') {
      try {
        const imageData = ctx.getImageData(0, 0, width, height);
        const d = imageData.data;
        // Penyesuaian kontras tinggi
        const factor = (259 * (128 + 255)) / (255 * (259 - 128));
        for (let i = 0; i < d.length; i += 4) {
          d[i] = factor * (d[i] - 128) + 128;
          d[i + 1] = factor * (d[i + 1] - 128) + 128;
          d[i + 2] = factor * (d[i + 2] - 128) + 128;
        }
        const code = window.jsQR(imageData.data, width, height, {
          inversionAttempts: 'attemptBoth'
        });
        if (code && code.data) {
          detectedRaw = code.data;
          detectionMethod = 'jsQR-contrast';
        }
      } catch (err) {
        // Abaikan
      }
    }

    // Analisis apakah QRIS atau QR biasa
    let parsedInfo = null;
    if (detectedRaw) {
      parsedInfo = window.QRISParser ? window.QRISParser.analyze(detectedRaw) : {
        isQR: true,
        isQRIS: false,
        raw: detectedRaw
      };
    } else {
      parsedInfo = {
        isQR: false,
        isQRIS: false,
        type: 'none',
        raw: ''
      };
    }

    return {
      file,
      fileName: file.name,
      fileSize: file.size,
      previewUrl: url,
      width,
      height,
      success: true,
      detectionMethod,
      ...parsedInfo
    };
  }

  /**
   * Pindai banyak file gambar secara berurutan dengan notifikasi progres
   * @param {FileList|Array<File>} files 
   * @param {Function} onProgress (completed, total, currentResult)
   */
  async scanBatch(files, onProgress) {
    const list = Array.from(files);
    const results = [];
    const total = list.length;

    for (let i = 0; i < total; i++) {
      const res = await this.scanFile(list[i]);
      results.push(res);
      if (typeof onProgress === 'function') {
        onProgress(i + 1, total, res);
      }
      // Berikan nafas bagi event loop agar UI tetap mulus 60 FPS
      await new Promise(r => setTimeout(r, 20));
    }

    return results;
  }
}

if (typeof window !== 'undefined') {
  window.QRDetectorEngine = QRDetectorEngine;
}
