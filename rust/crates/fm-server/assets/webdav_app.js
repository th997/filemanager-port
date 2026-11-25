(function () {
    const I18N = {
        zh: {
            htmlLang: 'zh-CN',
            docTitle: 'WebDAV 共享 - FP File Manager',
            pageTitle: '🌐 WebDAV 文件共享',
            filterPlaceholder: '筛选当前目录文件...',
            newFolder: '📂 新建文件夹',
            newFolderPrompt: '请输入新文件夹名称：',
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
            deleteBtn: '删除',
            confirmDelete: (name) => `确定要删除“${name}”吗？`,
            actionFailed: (status) => `操作失败（HTTP ${status}）`,
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
            docTitle: 'WebDAV Share - FP File Manager',
            pageTitle: '🌐 WebDAV File Sharing',
            filterPlaceholder: 'Filter files in current folder...',
            newFolder: '📂 New Folder',
            newFolderPrompt: 'Enter new folder name:',
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
            deleteBtn: 'Delete',
            confirmDelete: (name) => `Delete "${name}"?`,
            actionFailed: (status) => `Action failed (HTTP ${status})`,
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
            docTitle: 'WebDAV 共有 - FP File Manager',
            pageTitle: '🌐 WebDAV ファイル共有',
            filterPlaceholder: 'このフォルダ内のファイルを絞り込み...',
            newFolder: '📂 新規フォルダ',
            newFolderPrompt: '新しいフォルダ名を入力してください：',
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
            deleteBtn: '削除',
            confirmDelete: (name) => `「${name}」を削除しますか？`,
            actionFailed: (status) => `操作に失敗しました (HTTP ${status})`,
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
        document.getElementById('btn-new-folder').title = dict.newFolder;
        document.getElementById('btn-new-folder-text').innerText = dict.newFolder;
        document.getElementById('btn-upload-file').title = dict.uploadFileTitle;
        document.getElementById('btn-upload-file-text').innerText = dict.uploadFile;
        document.getElementById('btn-upload-folder').title = dict.uploadFolderTitle;
        document.getElementById('btn-upload-folder-text').innerText = dict.uploadFolder;
        document.getElementById('drop-overlay-text').innerText = dict.dropHint;
        const sel = document.getElementById('lang-select');
        if (sel) sel.value = currentLang;
    }

    function parsePathname(pathname) {
        return (pathname || '/')
            .split('/')
            .filter(Boolean)
            .map(s => {
                try { return decodeURIComponent(s); } catch (_) { return s; }
            })
            .join('/');
    }

    function encodeSlashPath(rel) {
        const clean = (rel || '').replace(/^\/+|\/+$/g, '');
        if (!clean) return '/';
        return '/' + clean.split('/').filter(Boolean).map(encodeURIComponent).join('/');
    }

    function buildDirUrl(rel) {
        const encoded = encodeSlashPath(rel);
        return encoded.endsWith('/') ? encoded : encoded + '/';
    }

    function buildListJsonUrl(rel) {
        return buildDirUrl(rel) + '?fm_json=1';
    }

    function buildFileInlineUrl(rel) {
        return encodeSlashPath(rel);
    }

    function buildFileDownloadUrl(rel) {
        return encodeSlashPath(rel) + '?download=1';
    }

    let currentPath = parsePathname(window.location.pathname);
    let allItems = [];
    let isReadOnly = false;
    let isSingleFile = false;

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
        if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico', 'heic'].includes(ext)) return '🖼️';
        if (['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv'].includes(ext)) return '🎬';
        if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a'].includes(ext)) return '🎵';
        if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'].includes(ext)) return '📦';
        if (['html', 'htm', 'js', 'css', 'json', 'xml', 'rs', 'dart', 'py', 'c', 'cpp', 'java', 'ts'].includes(ext)) return '💻';
        return '📄';
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

    function updateWriteControls() {
        const btns = document.getElementById('upload-buttons');
        if (btns) {
            btns.style.display = (isReadOnly || isSingleFile) ? 'none' : 'flex';
        }
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
            const deleteButton = (!isReadOnly && !isSingleFile)
                ? `<button class="btn-danger-ghost" data-delete-path="${safePath}" data-delete-name="${safeName}">${escapeHtml(dict.deleteBtn)}</button>`
                : '';

            if (item.is_dir) {
                html += `
                    <li class="file-item">
                        <a class="item-main folder-link" href="${buildDirUrl(item.path)}" data-path="${safePath}">
                            <span class="item-icon">${icon}</span>
                            <span class="item-name">${safeName}</span>
                        </a>
                        <div class="item-actions">
                            <span class="item-size">${escapeHtml(dict.folder)}</span>
                            ${deleteButton}
                        </div>
                    </li>
                `;
            } else {
                const inlineUrl = buildFileInlineUrl(item.path);
                const dlUrl = buildFileDownloadUrl(item.path);
                const sizeStr = formatSize(item.size);
                html += `
                    <li class="file-item">
                        <a class="item-main" href="${inlineUrl}" target="_blank">
                            <span class="item-icon">${icon}</span>
                            <span class="item-name">${safeName}</span>
                        </a>
                        <div class="item-actions">
                            <span class="item-size">${sizeStr}</span>
                            <a class="btn-download" href="${dlUrl}" download="${safeName}">${escapeHtml(dict.download)}</a>
                            ${deleteButton}
                        </div>
                    </li>
                `;
            }
        }
        listEl.innerHTML = html;
    }

    async function loadDir(path, pushHistory) {
        currentPath = (path || '').replace(/^\/+|\/+$/g, '');
        if (pushHistory && window.history && typeof window.history.pushState === 'function') {
            try {
                const targetHref = buildDirUrl(currentPath);
                if (window.location.pathname !== targetHref) {
                    window.history.pushState({ path: currentPath }, '', targetHref);
                }
            } catch (_) {}
        }
        renderBreadcrumbs(currentPath);
        document.getElementById('file-list').innerHTML = `<li class="empty-state">${escapeHtml(t().loading)}</li>`;

        try {
            const res = await fetch(buildListJsonUrl(currentPath), { credentials: 'same-origin' });
            if (!res.ok) {
                document.getElementById('file-list').innerHTML = `<li class="empty-state" style="color:#ef4444;">${escapeHtml(t().loadFailed(res.status))}</li>`;
                return;
            }
            const data = await res.json();
            isReadOnly = Boolean(data.read_only);
            isSingleFile = Boolean(data.single_file);
            allItems = Array.isArray(data.items) ? data.items : [];
            updateWriteControls();
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
            loadDir(target.getAttribute('data-path') || '', true);
        }
    });

    window.addEventListener('popstate', () => {
        loadDir(parsePathname(window.location.pathname), false);
    });

    document.getElementById('file-list').addEventListener('click', async (e) => {
        const folderLink = e.target.closest('.folder-link');
        if (folderLink) {
            e.preventDefault();
            loadDir(folderLink.getAttribute('data-path') || '', true);
            return;
        }
        const delBtn = e.target.closest('[data-delete-path]');
        if (delBtn) {
            e.preventDefault();
            const rel = delBtn.getAttribute('data-delete-path') || '';
            const name = delBtn.getAttribute('data-delete-name') || rel;
            if (!window.confirm(t().confirmDelete(name))) return;
            try {
                const res = await fetch(encodeSlashPath(rel), {
                    method: 'DELETE',
                    credentials: 'same-origin'
                });
                if (!res.ok) {
                    window.alert(t().actionFailed(res.status));
                    return;
                }
                loadDir(currentPath, false);
            } catch (err) {
                window.alert(t().networkError(err.message));
            }
        }
    });

    document.getElementById('filter-input').addEventListener('input', (e) => {
        renderItems(e.target.value);
    });

    document.getElementById('btn-new-folder').addEventListener('click', async () => {
        if (isReadOnly || isSingleFile) return;
        const name = window.prompt(t().newFolderPrompt);
        if (!name || !name.trim()) return;
        const clean = name.trim().replace(/[\\/]+/g, '');
        if (!clean || clean === '.' || clean === '..') return;
        const rel = currentPath ? `${currentPath}/${clean}` : clean;
        try {
            const res = await fetch(encodeSlashPath(rel), {
                method: 'MKCOL',
                credentials: 'same-origin'
            });
            if (!res.ok && res.status !== 201) {
                window.alert(t().actionFailed(res.status));
                return;
            }
            loadDir(currentPath, false);
        } catch (err) {
            window.alert(t().networkError(err.message));
        }
    });

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
        if (isReadOnly || isSingleFile) return;
        dragCounter++;
        const dropOverlay = getDropOverlay();
        if (dropOverlay) dropOverlay.classList.add('active');
    });

    window.addEventListener('dragleave', (e) => {
        e.preventDefault();
        if (isReadOnly || isSingleFile) return;
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
        if (isReadOnly || isSingleFile) return;

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

    function putSingleFile(targetUrl, file, onByteProgress) {
        return new Promise((resolve, reject) => {
            const xhr = new XMLHttpRequest();
            xhr.withCredentials = true;
            xhr.upload.onprogress = (event) => {
                if (event.lengthComputable) {
                    onByteProgress(event.loaded);
                }
            };
            xhr.onload = () => {
                if (xhr.status >= 200 && xhr.status < 300) {
                    onByteProgress(file.size);
                    resolve();
                } else {
                    reject({ status: xhr.status, detail: xhr.responseText });
                }
            };
            xhr.onerror = () => reject({ status: 0, detail: 'network' });
            xhr.open('PUT', targetUrl, true);
            xhr.send(file);
        });
    }

    async function ensureDirsForUpload(fileList) {
        const dirs = new Set();
        for (const item of fileList) {
            const rel = (item.relPath || item.file.name).replace(/^\/+/, '');
            const parts = rel.split('/').filter(Boolean);
            let accum = currentPath;
            for (let i = 0; i < parts.length - 1; i++) {
                accum = accum ? `${accum}/${parts[i]}` : parts[i];
                dirs.add(accum);
            }
        }
        const sorted = Array.from(dirs).sort((a, b) => a.split('/').length - b.split('/').length);
        for (const dir of sorted) {
            await fetch(encodeSlashPath(dir), {
                method: 'MKCOL',
                credentials: 'same-origin'
            });
        }
    }

    async function uploadFiles(fileList) {
        if (isReadOnly || isSingleFile || !fileList || fileList.length === 0) return;

        const statusEl = document.getElementById('upload-status');
        const textEl = document.getElementById('upload-status-text');
        const percentEl = document.getElementById('upload-status-percent');
        const fillEl = document.getElementById('progress-fill');

        statusEl.style.display = 'block';
        textEl.style.color = '';
        textEl.innerText = t().preparingUpload(fileList.length);
        percentEl.innerText = '0%';
        fillEl.style.width = '0%';

        const totalBytes = fileList.reduce((sum, item) => sum + (item.file.size || 0), 0);
        let uploadedBefore = 0;

        try {
            await ensureDirsForUpload(fileList);
            for (const item of fileList) {
                const rel = (item.relPath || item.file.name).replace(/^\/+/, '');
                const fullRel = currentPath ? `${currentPath}/${rel}` : rel;
                const url = encodeSlashPath(fullRel);
                await putSingleFile(url, item.file, (currentFileLoaded) => {
                    const loaded = Math.min(totalBytes, uploadedBefore + currentFileLoaded);
                    const pct = totalBytes > 0 ? Math.round((loaded / totalBytes) * 100) : 100;
                    fillEl.style.width = pct + '%';
                    percentEl.innerText = pct + '%';
                    textEl.innerText = t().uploadingProgress(formatSize(loaded), formatSize(totalBytes));
                });
                uploadedBefore += item.file.size || 0;
            }
            textEl.innerText = t().uploadSuccess(fileList.length);
            percentEl.innerText = '100%';
            fillEl.style.width = '100%';
            await loadDir(currentPath, false);
            setTimeout(() => {
                statusEl.style.display = 'none';
            }, 3000);
        } catch (err) {
            if (err && err.status && err.status > 0) {
                textEl.innerText = t().uploadFailed(err.status, err.detail);
            } else {
                textEl.innerText = t().uploadNetworkError;
            }
            textEl.style.color = '#ef4444';
        }
    }

    applyStaticI18n();
    loadDir(currentPath, false);
})();
