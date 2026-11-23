(function () {
    const I18N = {
        zh: {
            htmlLang: 'zh-CN',
            docTitle: '文件共享 - FP File Manager',
            pageTitle: '📁 局域网文件共享',
            filterPlaceholder: '筛选当前目录文件...',
            uploadFile: '📄 上传文件',
            uploadFileTitle: '上传单个或多个文件',
            uploadFolder: '📁 上传文件夹',
            uploadFolderTitle: '选择文件夹并递归上传内部所有文件',
            root: '根目录',
            loading: '正在加载文件列表...',
            emptyFolder: '文件夹为空',
            noMatch: '没有找到匹配的文件',
            folder: '文件夹',
            download: '下载',
            itemCount: (n) => `${n} 项内容`,
            loadFailed: (status) => `加载目录失败（HTTP ${status}）`,
            networkError: (msg) => `网络请求出错：${msg}`,
            preparingUpload: (n) => `正在准备上传 ${n} 个文件...`,
            uploadingProgress: (loaded, total) => `正在上传 (${loaded} / ${total})...`,
            uploadSuccess: (n) => `上传成功（共 ${n} 个文件）`,
            uploadFailed: (status, detail) => `上传失败（HTTP ${status}）：${detail || '请重试'}`,
            uploadNetworkError: '网络连接异常，上传失败',
            dropHint: '释放鼠标以上传文件或文件夹到当前目录',
        },
        en: {
            htmlLang: 'en',
            docTitle: 'LAN File Sharing - FP File Manager',
            pageTitle: '📁 LAN File Sharing',
            filterPlaceholder: 'Filter files in current folder...',
            uploadFile: '📄 Upload Files',
            uploadFileTitle: 'Upload one or more files',
            uploadFolder: '📁 Upload Folder',
            uploadFolderTitle: 'Select a folder and upload all files recursively',
            root: 'Root',
            loading: 'Loading files...',
            emptyFolder: 'Folder is empty',
            noMatch: 'No matching files found',
            folder: 'Folder',
            download: 'Download',
            itemCount: (n) => n === 1 ? '1 item' : `${n} items`,
            loadFailed: (status) => `Failed to load folder (HTTP ${status})`,
            networkError: (msg) => `Network error: ${msg}`,
            preparingUpload: (n) => `Preparing to upload ${n} file(s)...`,
            uploadingProgress: (loaded, total) => `Uploading (${loaded} / ${total})...`,
            uploadSuccess: (n) => `Uploaded ${n} file(s) successfully`,
            uploadFailed: (status, detail) => `Upload failed (HTTP ${status}): ${detail || 'Please retry'}`,
            uploadNetworkError: 'Network error during upload',
            dropHint: 'Drop files or folders to upload to this folder',
        },
        ja: {
            htmlLang: 'ja',
            docTitle: 'LAN ファイル共有 - FP File Manager',
            pageTitle: '📁 LAN ファイル共有',
            filterPlaceholder: 'このフォルダ内のファイルを絞り込み...',
            uploadFile: '📄 ファイルを選択',
            uploadFileTitle: '1つ以上のファイルをアップロード',
            uploadFolder: '📁 フォルダを選択',
            uploadFolderTitle: 'フォルダ内のファイルを再帰的にアップロード',
            root: 'ルート',
            loading: 'ファイル一覧を読み込み中...',
            emptyFolder: 'フォルダは空です',
            noMatch: '一致するファイルが見つかりません',
            folder: 'フォルダ',
            download: 'ダウンロード',
            itemCount: (n) => `${n} 件`,
            loadFailed: (status) => `フォルダの読み込みに失敗しました (HTTP ${status})`,
            networkError: (msg) => `ネットワークエラー: ${msg}`,
            preparingUpload: (n) => `${n} 件のファイルをアップロード準備中...`,
            uploadingProgress: (loaded, total) => `アップロード中 (${loaded} / ${total})...`,
            uploadSuccess: (n) => `${n} 件のファイルをアップロードしました`,
            uploadFailed: (status, detail) => `アップロードに失敗しました (HTTP ${status}): ${detail || '再試行してください'}`,
            uploadNetworkError: 'ネットワークエラーのためアップロードに失敗しました',
            dropHint: 'ここにドロップして現在のフォルダにアップロード',
        }
    };

    const EXTERNAL_I18N = (typeof window !== 'undefined' && window.__FM_I18N__) || {};
    for (const code of ['zh', 'en', 'ja']) {
        if (EXTERNAL_I18N[code]) {
            Object.assign(I18N[code], EXTERNAL_I18N[code]);
        }
    }

    function detectLang() {
        try {
            const saved = localStorage.getItem('fm_lan_lang');
            if (saved && I18N[saved]) return saved;
        } catch (_) {}
        const serverLang = document.documentElement.getAttribute('data-server-lang');
        if (serverLang && I18N[serverLang]) return serverLang;
        const nav = (navigator.language || 'en').toLowerCase();
        if (nav.startsWith('zh')) return 'zh';
        if (nav.startsWith('ja')) return 'ja';
        return 'en';
    }

    let currentLang = detectLang();
    function t() {
        return I18N[currentLang] || I18N.en;
    }

    function applyStaticI18n() {
        const dict = t();
        document.documentElement.lang = dict.htmlLang;
        document.title = dict.docTitle;
        document.getElementById('page-title').innerText = dict.pageTitle;
        document.getElementById('filter-input').placeholder = dict.filterPlaceholder;
        document.getElementById('btn-upload-file').title = dict.uploadFileTitle;
        document.getElementById('btn-upload-file-text').innerText = dict.uploadFile;
        document.getElementById('btn-upload-folder').title = dict.uploadFolderTitle;
        document.getElementById('btn-upload-folder-text').innerText = dict.uploadFolder;
        document.getElementById('drop-overlay-text').innerText = dict.dropHint;
        const sel = document.getElementById('lang-select');
        if (sel) sel.value = currentLang;
    }

    let currentPath = '';
    let allItems = [];
    let isReadOnly = false;

    const shareToken = new URLSearchParams(window.location.search).get('token');
    function withToken(url) {
        if (!shareToken) return url;
        return url + (url.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(shareToken);
    }

    function escapeHtml(str) {
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }

    function formatSize(bytes) {
        if (bytes == null || bytes === undefined) return '-';
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + ' MB';
        return (bytes / 1073741824).toFixed(2) + ' GB';
    }

    function getFileIcon(name, isDir) {
        if (isDir) return '📁';
        const ext = (name.split('.').pop() || '').toLowerCase();
        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico'].includes(ext)) return '🖼️';
        if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv'].includes(ext)) return '🎬';
        if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].includes(ext)) return '🎵';
        if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'].includes(ext)) return '📦';
        if (['html', 'htm', 'js', 'css', 'json', 'xml', 'rs', 'dart', 'py', 'c', 'cpp', 'java', 'ts'].includes(ext)) return '💻';
        if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md'].includes(ext)) return '📄';
        return '📄';
    }

    function buildListUrl(path) {
        const clean = (path || '').replace(/^\/+|\/+$/g, '');
        if (!clean) return withToken('/api/list');
        return withToken('/api/list/' + clean.split('/').map(encodeURIComponent).join('/'));
    }

    function buildDownloadUrl(path) {
        const clean = (path || '').replace(/^\/+|\/+$/g, '');
        return withToken('/download/' + clean.split('/').map(encodeURIComponent).join('/'));
    }

    function renderBreadcrumbs(path) {
        const bar = document.getElementById('breadcrumb-bar');
        const clean = (path || '').replace(/^\/+|\/+$/g, '');
        let html = `<span class="breadcrumb-item" data-path="">${escapeHtml(t().root)}</span>`;
        if (clean) {
            const parts = clean.split('/');
            let accum = '';
            for (let i = 0; i < parts.length; i++) {
                accum = accum ? (accum + '/' + parts[i]) : parts[i];
                html += '<span class="breadcrumb-sep">/</span>';
                if (i === parts.length - 1) {
                    html += `<span class="breadcrumb-current">${escapeHtml(parts[i])}</span>`;
                } else {
                    html += `<span class="breadcrumb-item" data-path="${escapeHtml(accum)}">${escapeHtml(parts[i])}</span>`;
                }
            }
        }
        bar.innerHTML = html;
    }

    function renderItems(filterText) {
        const dict = t();
        const listEl = document.getElementById('file-list');
        const query = (filterText || '').trim().toLowerCase();
        const filtered = query
            ? allItems.filter(item => item.name.toLowerCase().includes(query))
            : allItems;

        document.getElementById('item-count-text').innerText = dict.itemCount(filtered.length);

        if (filtered.length === 0) {
            listEl.innerHTML = query
                ? `<li class="empty-state">${escapeHtml(dict.noMatch)}</li>`
                : `<li class="empty-state">${escapeHtml(dict.emptyFolder)}</li>`;
            return;
        }

        let html = '';
        for (const item of filtered) {
            const icon = getFileIcon(item.name, item.is_dir);
            const safeName = escapeHtml(item.name);
            const safePath = escapeHtml(item.path);

            if (item.is_dir) {
                html += `
                    <li class="file-item">
                        <div class="item-main folder-link" data-path="${safePath}">
                            <span class="item-icon">${icon}</span>
                            <span class="item-name">${safeName}</span>
                        </div>
                        <div class="item-actions">
                            <span class="item-size">${escapeHtml(dict.folder)}</span>
                        </div>
                    </li>
                `;
            } else {
                const dlUrl = buildDownloadUrl(item.path);
                const sizeStr = formatSize(item.size);
                html += `
                    <li class="file-item">
                        <a class="item-main" href="${dlUrl}" target="_blank">
                            <span class="item-icon">${icon}</span>
                            <span class="item-name">${safeName}</span>
                        </a>
                        <div class="item-actions">
                            <span class="item-size">${sizeStr}</span>
                            <a class="btn-download" href="${dlUrl}" download="${safeName}">${escapeHtml(dict.download)}</a>
                        </div>
                    </li>
                `;
            }
        }
        listEl.innerHTML = html;
    }

    async function loadDir(path) {
        currentPath = (path || '').replace(/^\/+|\/+$/g, '');
        renderBreadcrumbs(currentPath);
        document.getElementById('file-list').innerHTML = `<li class="empty-state">${escapeHtml(t().loading)}</li>`;

        try {
            const res = await fetch(buildListUrl(currentPath));
            if (!res.ok) {
                document.getElementById('file-list').innerHTML = `<li class="empty-state" style="color:#ef4444;">${escapeHtml(t().loadFailed(res.status))}</li>`;
                return;
            }
            allItems = await res.json();
            document.getElementById('filter-input').value = '';
            renderItems('');
        } catch (err) {
            document.getElementById('file-list').innerHTML = `<li class="empty-state" style="color:#ef4444;">${escapeHtml(t().networkError(err.message))}</li>`;
        }
    }

    document.getElementById('lang-select').addEventListener('change', (e) => {
        const next = e.target.value;
        if (!I18N[next]) return;
        currentLang = next;
        try { localStorage.setItem('fm_lan_lang', next); } catch (_) {}
        applyStaticI18n();
        renderBreadcrumbs(currentPath);
        renderItems(document.getElementById('filter-input').value);
    });

    document.getElementById('breadcrumb-bar').addEventListener('click', (e) => {
        const target = e.target.closest('.breadcrumb-item');
        if (target) {
            loadDir(target.getAttribute('data-path') || '');
        }
    });

    document.getElementById('file-list').addEventListener('click', (e) => {
        const folderLink = e.target.closest('.folder-link');
        if (folderLink) {
            e.preventDefault();
            loadDir(folderLink.getAttribute('data-path') || '');
        }
    });

    document.getElementById('filter-input').addEventListener('input', (e) => {
        renderItems(e.target.value);
    });

    async function checkConfig() {
        try {
            const res = await fetch(withToken('/api/config'));
            if (res.ok) {
                const cfg = await res.json();
                isReadOnly = Boolean(cfg.read_only);
                if (isReadOnly) {
                    const btns = document.getElementById('upload-buttons');
                    if (btns) btns.style.display = 'none';
                }
            }
        } catch (_) {}
    }

    document.getElementById('btn-upload-file').addEventListener('click', () => {
        document.getElementById('file-input').click();
    });

    document.getElementById('btn-upload-folder').addEventListener('click', () => {
        document.getElementById('folder-input').click();
    });

    document.getElementById('file-input').addEventListener('change', (e) => {
        if (e.target.files && e.target.files.length > 0) {
            const filesToUpload = Array.from(e.target.files).map(f => ({
                file: f,
                relPath: f.name
            }));
            uploadFiles(filesToUpload);
            e.target.value = '';
        }
    });

    document.getElementById('folder-input').addEventListener('change', (e) => {
        if (e.target.files && e.target.files.length > 0) {
            const filesToUpload = Array.from(e.target.files).map(f => ({
                file: f,
                relPath: f.webkitRelativePath || f.name
            }));
            uploadFiles(filesToUpload);
            e.target.value = '';
        }
    });

    async function getFilesFromEntry(entry, path = '') {
        if (entry.isFile) {
            return new Promise((resolve) => {
                entry.file(f => {
                    resolve([{ file: f, relPath: (path ? path + '/' : '') + f.name }]);
                }, () => resolve([]));
            });
        } else if (entry.isDirectory) {
            const dirReader = entry.createReader();
            const entries = await new Promise((resolve) => {
                let all = [];
                function readBatch() {
                    dirReader.readEntries((results) => {
                        if (!results || results.length === 0) {
                            resolve(all);
                        } else {
                            all = all.concat(results);
                            readBatch();
                        }
                    }, () => resolve(all));
                }
                readBatch();
            });
            let list = [];
            const nextPath = path ? (path + '/' + entry.name) : entry.name;
            for (const child of entries) {
                const sub = await getFilesFromEntry(child, nextPath);
                list = list.concat(sub);
            }
            return list;
        }
        return [];
    }

    let dragCounter = 0;
    const getDropOverlay = () => document.getElementById('drop-overlay');

    window.addEventListener('dragenter', (e) => {
        e.preventDefault();
        if (isReadOnly) return;
        dragCounter++;
        const dropOverlay = getDropOverlay();
        if (dropOverlay) dropOverlay.classList.add('active');
    });

    window.addEventListener('dragleave', (e) => {
        e.preventDefault();
        if (isReadOnly) return;
        dragCounter--;
        if (dragCounter <= 0) {
            dragCounter = 0;
            const dropOverlay = getDropOverlay();
            if (dropOverlay) dropOverlay.classList.remove('active');
        }
    });

    window.addEventListener('dragover', (e) => {
        e.preventDefault();
    });

    window.addEventListener('drop', async (e) => {
        e.preventDefault();
        dragCounter = 0;
        const dropOverlay = getDropOverlay();
        if (dropOverlay) dropOverlay.classList.remove('active');
        if (isReadOnly) return;

        const items = e.dataTransfer && e.dataTransfer.items;
        let filesToUpload = [];

        if (items && items.length > 0 && items[0].webkitGetAsEntry) {
            for (let i = 0; i < items.length; i++) {
                const entry = items[i].webkitGetAsEntry();
                if (entry) {
                    const sub = await getFilesFromEntry(entry);
                    filesToUpload = filesToUpload.concat(sub);
                }
            }
        } else if (e.dataTransfer && e.dataTransfer.files) {
            filesToUpload = Array.from(e.dataTransfer.files).map(f => ({
                file: f,
                relPath: f.name
            }));
        }

        if (filesToUpload.length > 0) {
            uploadFiles(filesToUpload);
        }
    });

    function uploadFiles(fileList) {
        if (isReadOnly || !fileList || fileList.length === 0) return;

        const statusEl = document.getElementById('upload-status');
        const textEl = document.getElementById('upload-status-text');
        const percentEl = document.getElementById('upload-status-percent');
        const fillEl = document.getElementById('progress-fill');

        statusEl.style.display = 'block';
        textEl.style.color = '';
        textEl.innerText = t().preparingUpload(fileList.length);
        percentEl.innerText = '0%';
        fillEl.style.width = '0%';

        const formData = new FormData();
        for (const item of fileList) {
            formData.append('files', item.file, item.relPath);
        }

        const url = withToken('/api/upload?dir=' + encodeURIComponent(currentPath));

        const xhr = new XMLHttpRequest();
        xhr.upload.onprogress = (event) => {
            if (event.lengthComputable) {
                const percent = Math.round((event.loaded / event.total) * 100);
                fillEl.style.width = percent + '%';
                percentEl.innerText = percent + '%';
                textEl.innerText = t().uploadingProgress(formatSize(event.loaded), formatSize(event.total));
            }
        };

        xhr.onload = () => {
            if (xhr.status >= 200 && xhr.status < 300) {
                textEl.innerText = t().uploadSuccess(fileList.length);
                percentEl.innerText = '100%';
                fillEl.style.width = '100%';
                loadDir(currentPath);
                setTimeout(() => {
                    statusEl.style.display = 'none';
                }, 3000);
            } else {
                textEl.innerText = t().uploadFailed(xhr.status, xhr.responseText);
                textEl.style.color = '#ef4444';
            }
        };

        xhr.onerror = () => {
            textEl.innerText = t().uploadNetworkError;
            textEl.style.color = '#ef4444';
        };

        xhr.open('POST', url, true);
        xhr.send(formData);
    }

    applyStaticI18n();
    checkConfig();
    loadDir('');
})();
