
__SHARED_RENDERER_JS__

// Safe escaping for single-quoted JS string literals inside HTML attributes (onclick="fn('...')")
function escapeJSAttr(str) {
    return (str || '')
        .replace(/\\/g, '\\\\')
        .replace(/'/g, "\\'")
        .replace(/\n/g, '\\n')
        .replace(/\r/g, '\\r')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

let state = __INITIAL_STATE_JSON__;
let ui = {
    filterKind: 'all',     // 'all' | 'recent' | 'favorites' | 'notes' | 'status:unread' | 'status:reading' | 'status:completed' | 'cat:...'
    filterTitle: '我的文库',
    activeTag: null,
    tagFilterQuery: '',
    searchQuery: '',
    sortOrder: 'title',
    sortAscending: true,
    noteSortOrder: 'page', // 'page' | 'newest' | 'oldest' | 'color'
    inspectorTab: 0,       // 0: Info & PDFs, 1: Notes (LaTeX), 2: Related & Links
    inspectorCollapsed: false,
    inspectorShowingSummary: true,
    treeExpanded: true,
    expandedPaperIds: {}
};
let draggedPaperId = null;
let metaSaveTimer = null;
let pendingMetadata = null;
let isComposingMeta = false;

function formatFileSize(sizeKB) {
    if (!sizeKB || sizeKB <= 0) return '';
    if (sizeKB >= 1024) {
        return (sizeKB / 1024).toFixed(1) + ' MB';
    }
    return sizeKB + ' KB';
}

function paperTotalNoteCount(p) {
    const annCount = (p.annotations ? p.annotations.length : 0);
    const docCount = (p.noteDocuments ? p.noteDocuments.length : 0);
    return annCount + docCount;
}

function formatZoteroCreator(authorsStr) {
    const raw = (authorsStr || '').trim();
    if (!raw) return '—';
    const parts = raw.split(/\s*[,;，；]\s*|\s+and\s+/i).map(s => s.trim()).filter(Boolean);
    if (parts.length === 0) return '—';
    const first = parts[0];
    const words = first.split(/\s+/).filter(Boolean);
    let displayFirst = first;
    if (words.length >= 2 && /^[A-Za-z.\-]+$/.test(words[words.length - 1])) {
        displayFirst = words[words.length - 1];
    }
    if (parts.length > 1) {
        return displayFirst + ' 等';
    }
    return displayFirst;
}

function sendBridge(payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.libraryBridge) {
        window.webkit.messageHandlers.libraryBridge.postMessage(payload);
    }
}

window.updateLibraryState = function(newState) {
    state = newState;
    if (ui.filterKind.startsWith('cat:') && !(state.categories || []).includes(ui.filterKind.slice(4))) {
        ui.filterKind = 'all';
        ui.filterTitle = '我的文库';
        ui.activeTag = null;
    }
    if (!state.selectedPaperId && state.papers && state.papers.length > 0) {
        state.selectedPaperId = state.papers[0].id;
    }
    renderAll();
};

window.focusLibrarySearch = function() {
    const input = document.getElementById('searchInput');
    if (input) { input.focus(); input.select(); }
};

window.openCreatePaperModal = function() {
    document.getElementById('mTitle').value = '';
    document.getElementById('mAuthors').value = '';
    document.getElementById('mYear').value = new Date().getFullYear().toString();
    document.getElementById('mVenue').value = 'arXiv';
    const defaultCat = ui.filterKind.startsWith('cat:') ? ui.filterKind.slice(4) : '大模型架构 (LLM)';
    document.getElementById('mCategory').value = defaultCat;
    document.getElementById('mTags').value = '';
    document.getElementById('mLocalArxivId').value = '';
    document.getElementById('modalOrigStatus').textContent = '点击选择或通过上方按钮自动配对…';
    document.getElementById('modalTransStatus').textContent = '点击选择或通过上方按钮自动配对…';
    const arxivInput = document.getElementById('mArxivInput');
    if (arxivInput) arxivInput.value = '';
    const arxivCat = document.getElementById('mArxivCategory');
    if (arxivCat) arxivCat.value = defaultCat;
    if (window.switchModalTab) window.switchModalTab('local');
    document.getElementById('createModal').classList.add('open');
};

window.switchModalTab = function(tab) {
    const isArxiv = (tab === 'arxiv');
    const tabLocal = document.getElementById('modalTabLocal');
    const tabArxiv = document.getElementById('modalTabArxiv');
    const secLocal = document.getElementById('modalLocalSection');
    const secArxiv = document.getElementById('modalArxivSection');
    if (tabLocal) tabLocal.classList.toggle('active', !isArxiv);
    if (tabArxiv) tabArxiv.classList.toggle('active', isArxiv);
    if (secLocal) secLocal.style.display = isArxiv ? 'none' : 'block';
    if (secArxiv) secArxiv.style.display = isArxiv ? 'block' : 'none';
};

window.submitArxivImportModal = function() {
    const inputEl = document.getElementById('mArxivInput');
    const input = (inputEl ? inputEl.value : '').trim();
    if (!input) {
        alert('请输入 arXiv ID 或论文链接，例如：1706.03762v7');
        return;
    }
    const catEl = document.getElementById('mArxivCategory');
    const category = (catEl ? catEl.value : '大模型架构 (LLM)').trim();
    const btn = document.getElementById('btnSubmitArxiv');
    if (btn) {
        btn.disabled = true;
        btn.textContent = '正在拉取元数据与下载 PDF…';
    }
    sendBridge({ action: 'createFromArxivId', arxivId: input, category });
    closeCreatePaperModal();
    setTimeout(() => {
        if (btn) {
            btn.disabled = false;
            btn.textContent = '解析元数据并下载创建';
        }
    }, 1500);
};

window.closeCreatePaperModal = function() {
    document.getElementById('createModal').classList.remove('open');
};

window.onModalPDFsPicked = function(info) {
    if (info.origName) {
        document.getElementById('modalOrigStatus').textContent = '已选: ' + info.origName;
    }
    if (info.transName) {
        document.getElementById('modalTransStatus').textContent = '已选: ' + info.transName;
    }
    const tEl = document.getElementById('mTitle');
    const aEl = document.getElementById('mAuthors');
    const yEl = document.getElementById('mYear');
    if (!tEl.value && info.title) tEl.value = info.title;
    if (!aEl.value && info.authors) aEl.value = info.authors;
    if (info.year) yEl.value = info.year;
    document.getElementById('mLocalArxivId').value = info.arxivId || '';
};

window.submitCreatePaperModal = function() {
    sendBridge({
        action: 'confirmCreatePaper',
        title: document.getElementById('mTitle').value,
        authors: document.getElementById('mAuthors').value,
        year: document.getElementById('mYear').value,
        venue: document.getElementById('mVenue').value,
        category: document.getElementById('mCategory').value,
        tags: document.getElementById('mTags').value,
        arxivId: document.getElementById('mLocalArxivId').value
    });
    closeCreatePaperModal();
};

window.resolveNativeDropZone = function(x, y) {
    if (ui.inspectorCollapsed || ui.inspectorShowingSummary || ui.inspectorTab !== 0) return 'library';
    const origSlot = document.getElementById('slotOriginal');
    if (origSlot) {
        const r = origSlot.getBoundingClientRect();
        if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return 'original';
    }
    const transSlot = document.getElementById('slotTranslated');
    if (transSlot) {
        const r = transSlot.getBoundingClientRect();
        if (x >= r.left && x <= r.right && y >= r.top && y <= r.bottom) return 'translated';
    }
    return 'library';
};

window.updateNativeDragHover = function(x, y) {
    const zone = window.resolveNativeDropZone(x, y);
    window.setNativeDragState(true, zone);
    return zone;
};

function syncDropSlotRects() {
    const active = (!ui.inspectorCollapsed && !ui.inspectorShowingSummary && ui.inspectorTab === 0);
    const origSlot = document.getElementById('slotOriginal');
    const transSlot = document.getElementById('slotTranslated');
    if (active && origSlot && transSlot) {
        const r1 = origSlot.getBoundingClientRect();
        const r2 = transSlot.getBoundingClientRect();
        sendBridge({
            action: 'syncDropSlotRects',
            active: true,
            origRect: [r1.left, r1.top, r1.width, r1.height],
            transRect: [r2.left, r2.top, r2.width, r2.height]
        });
    } else {
        sendBridge({
            action: 'syncDropSlotRects',
            active: false,
            origRect: [],
            transRect: []
        });
    }
}

window.setNativeDragState = function(active, zone) {
    const ov = document.getElementById('dragOverlay');
    const txt = document.getElementById('dragOverlayText');
    const origSlot = document.getElementById('slotOriginal');
    const transSlot = document.getElementById('slotTranslated');
    if (origSlot) origSlot.classList.toggle('drag-target', active && zone === 'original');
    if (transSlot) transSlot.classList.toggle('drag-target', active && zone === 'translated');

    if (!active) {
        ov.classList.remove('visible');
        return;
    }
    if (zone === 'original' || zone === 'translated') {
        ov.classList.remove('visible');
    } else {
        txt.textContent = '释放 PDF 文件即可智能识别中英双栏并导入文献库';
        ov.classList.add('visible');
    }
};

function setFilter(kind, title) {
    ui.filterKind = kind;
    ui.filterTitle = title;
    renderAll();
}

function toggleRootTree(evt) {
    if (evt) evt.stopPropagation();
    ui.treeExpanded = !ui.treeExpanded;
    renderSidebar();
}

function toggleTag(tag) {
    ui.activeTag = (ui.activeTag === tag) ? null : tag;
    renderAll();
}

function onTagFilterInput(val) {
    ui.tagFilterQuery = (val || '').trim();
    renderTagPanelOnly();
}

function clearTagFilter() {
    ui.activeTag = null;
    ui.tagFilterQuery = '';
    const input = document.getElementById('tagFilterInput');
    if (input) input.value = '';
    renderAll();
}

function setInspectorTab(idx) {
    flushPendingMetadata();
    ui.inspectorShowingSummary = false;
    ui.inspectorTab = idx;
    [0, 1, 2].forEach(i => {
        const el = document.getElementById('inspTab' + i);
        if (el) el.classList.toggle('active', i === idx);
    });
    renderInspector();
}

function toggleInspectorPane() {
    ui.inspectorCollapsed = !ui.inspectorCollapsed;
    document.getElementById('workspace').classList.toggle('inspector-collapsed', ui.inspectorCollapsed);
    syncDropSlotRects();
}

function activateInspectorSection(sectionKey) {
    if (ui.inspectorCollapsed) {
        ui.inspectorCollapsed = false;
        document.getElementById('workspace').classList.remove('inspector-collapsed');
    }
    if (!state.selectedPaperId && state.papers && state.papers.length > 0) {
        state.selectedPaperId = state.papers[0].id;
    }
    ui.inspectorShowingSummary = false;
    if (sectionKey === 'notes') {
        setInspectorTab(1);
        return;
    }
    if (sectionKey === 'related') {
        setInspectorTab(2);
        return;
    }
    setInspectorTab(0);
    setTimeout(() => {
        if (sectionKey === 'pdfs') {
            const el = document.getElementById('slotOriginal');
            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        } else if (sectionKey === 'collection') {
            const el = document.getElementById('inspCategory');
            if (el) { el.scrollIntoView({ behavior: 'smooth', block: 'center' }); el.focus(); }
        } else if (sectionKey === 'tags') {
            const el = document.getElementById('inspTags');
            if (el) { el.scrollIntoView({ behavior: 'smooth', block: 'center' }); el.focus(); }
        } else if (sectionKey === 'info') {
            const el = document.getElementById('inspTitle');
            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
        } else {
            const body = document.getElementById('inspectorBody');
            if (body) body.scrollTop = 0;
        }
    }, 30);
}

function openSelectedPaperIfAny(evt) {
    if (evt) evt.stopPropagation();
    const pid = state.selectedPaperId || ((state.papers && state.papers[0]) ? state.papers[0].id : null);
    if (pid) openPaperDual(pid, evt);
}

function triggerAutoExtractSelected() {
    const pid = state.selectedPaperId || ((state.papers && state.papers[0]) ? state.papers[0].id : null);
    if (pid) {
        sendBridge({ action: 'autoExtractMetadata', paperId: pid });
    } else {
        openCreatePaperModal();
    }
}

function openAttachmentQuickMenu(evt) {
    if (evt) { evt.preventDefault(); evt.stopPropagation(); }
    const pid = state.selectedPaperId || ((state.papers && state.papers[0]) ? state.papers[0].id : null);
    if (!pid) { openCreatePaperModal(); return; }
    const pidAttr = escapeJSAttr(pid);
    const menu = document.getElementById('ctxMenu');
    menu.innerHTML = `
        <div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'importOrReplacePDF', paperId:'${pidAttr}', side:'original'})"><span>导入 / 替换原版 PDF (EN)…</span></div>
        <div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'importOrReplacePDF', paperId:'${pidAttr}', side:'translated'})"><span>导入 / 替换中文译版 PDF (ZH)…</span></div>
        <div class="ctx-sep"></div>
        <div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'addAdditionalPDF', paperId:'${pidAttr}'})"><span>＋ 向本论文集添加附加 PDF…</span></div>
        <div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'addLocalAttachment', paperId:'${pidAttr}'})"><span>挂载本地附件 / 代码文件…</span></div>
    `;
    showDropdownMenuNearEvent(menu, evt);
}

function openNoteQuickMenu(evt) {
    if (evt) { evt.preventDefault(); evt.stopPropagation(); }
    const pid = state.selectedPaperId || ((state.papers && state.papers[0]) ? state.papers[0].id : null);
    const pidAttr = escapeJSAttr(pid || '');
    const menu = document.getElementById('ctxMenu');
    menu.innerHTML = `
        ${pid ? `<div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'openPaperNotesSidebar', paperId:'${pidAttr}'})"><span>打开论文与右侧笔记</span></div>` : ''}
        ${pid ? `<div class="ctx-item" onclick="closeContextMenu(); activateInspectorSection('notes')"><span>在右侧栏查看该论文笔记</span></div>` : ''}
        <div class="ctx-sep"></div>
        <div class="ctx-item" onclick="closeContextMenu(); setFilter('notes', '全局笔记')"><span>查看全局笔记流</span></div>
    `;
    showDropdownMenuNearEvent(menu, evt);
}

function openSortAndViewMenu(evt) {
    if (evt) { evt.preventDefault(); evt.stopPropagation(); }
    const menu = document.getElementById('ctxMenu');
    const checkMark = (cond) => cond ? '<span>✓</span>' : '';
    menu.innerHTML = `
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('title')"><span>按标题排序</span>${checkMark(ui.sortOrder === 'title')}</div>
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('authors')"><span>按创建者排序</span>${checkMark(ui.sortOrder === 'authors')}</div>
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('recent')"><span>按最近阅读排序</span>${checkMark(ui.sortOrder === 'recent')}</div>
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('year')"><span>按发表年份排序</span>${checkMark(ui.sortOrder === 'year')}</div>
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('added')"><span>按添加时间排序</span>${checkMark(ui.sortOrder === 'added')}</div>
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('notes')"><span>按笔记数量排序</span>${checkMark(ui.sortOrder === 'notes')}</div>
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('status')"><span>按阅读状态排序</span>${checkMark(ui.sortOrder === 'status')}</div>
        <div class="ctx-item" onclick="closeContextMenu(); sortByColumn('custom')"><span>按自定义顺序</span>${checkMark(ui.sortOrder === 'custom')}</div>
        <div class="ctx-sep"></div>
        <div class="ctx-item" onclick="closeContextMenu(); toggleSortDirection()"><span>切换升序 / 降序 (${ui.sortAscending ? '当前升序 ↑' : '当前降序 ↓'})</span></div>
    `;
    showDropdownMenuNearEvent(menu, evt);
}

function showDropdownMenuNearEvent(menu, evt) {
    menu.classList.add('open');
    const x = evt ? Math.min(evt.clientX, window.innerWidth - 235) : 200;
    const y = evt ? Math.min(evt.clientY + 6, window.innerHeight - 310) : 48;
    menu.style.left = Math.max(8, x) + 'px';
    menu.style.top = Math.max(8, y) + 'px';
}

function toggleRowExpand(paperId, evt) {
    if (evt) evt.stopPropagation();
    ui.expandedPaperIds[paperId] = !ui.expandedPaperIds[paperId];
    renderCenter();
}

function handleCenterBlankClick(evt) {
    if (!evt || !evt.target) return;
    if (evt.target.closest('tr.zotero-row') || evt.target.closest('tr.zotero-subrow') || evt.target.closest('th')) {
        return;
    }
    flushPendingMetadata();
    ui.inspectorShowingSummary = true;
    renderInspector();
}

function selectPaper(paperId, openInspectorDetail) {
    if (paperId !== state.selectedPaperId) flushPendingMetadata();
    const changed = (state.selectedPaperId !== paperId);
    state.selectedPaperId = paperId;
    if (openInspectorDetail) {
        ui.inspectorShowingSummary = false;
    }
    sendBridge({ action: 'selectPaper', paperId });
    // CRITICAL: Update .selected class in-place without replacing centerContent.innerHTML
    // so DOM nodes stay alive between click #1 and click #2 of a double-click (ondblclick)!
    document.querySelectorAll('[data-paper-id]').forEach(el => {
        el.classList.toggle('selected', el.getAttribute('data-paper-id') === paperId);
    });
    if (changed || openInspectorDetail) {
        renderInspector();
    }
}

function openPaperDual(paperId, evt) {
    if (evt) evt.stopPropagation();
    closeContextMenu();
    state.selectedPaperId = paperId;
    sendBridge({ action: 'openPaper', paperId });
}

function toggleStar(paperId, evt) {
    if (evt) evt.stopPropagation();
    closeContextMenu();
    sendBridge({ action: 'toggleStar', paperId });
}

function renderCategorySubmenu(p) {
    const pidAttr = escapeJSAttr(p.id);
    const cats = (state.categories && state.categories.length > 0) ? state.categories : ['大模型架构 (LLM)'];
    let html = cats.map(cat => `
        <div class="ctx-item" onclick="closeContextMenu(); setPaperCategory('${pidAttr}', '${escapeJSAttr(cat)}')">
            <span>${escapeHTML(cat)}</span>
            ${p.category === cat ? '<span style="font-weight:bold;color:var(--accent);">✓</span>' : ''}
        </div>
    `).join('');
    html += `
        <div class="ctx-sep"></div>
        <div class="ctx-item" onclick="closeContextMenu(); promptNewCategoryForPaper('${pidAttr}')">
            <span>＋ 新建分类…</span>
        </div>
    `;
    return html;
}

function setPaperCategory(paperId, category) {
    sendBridge({ action: 'setPaperCategory', paperId, category });
}

function promptNewCategoryForPaper(paperId) {
    flushPendingMetadata();
    sendBridge({ action: 'createCategory', paperId });
}

function openPaperContextMenu(paperId, evt) {
    if (evt) {
        evt.preventDefault();
        evt.stopPropagation();
    }
    selectPaper(paperId, true);
    const p = (state.papers || []).find(item => item.id === paperId);
    if (!p) return;
    const menu = document.getElementById('ctxMenu');
    const pidAttr = escapeJSAttr(p.id);
    const hasArxiv = !!(p.arxivId && p.arxivId.trim().length > 0);
    const arxivDisabled = hasArxiv ? '' : 'disabled';
    const arxivAction = hasArxiv ? `closeContextMenu(); sendBridge({action:'openArxivURL', paperId:'${pidAttr}'})` : '';
    const hjfyAction = hasArxiv ? `closeContextMenu(); sendBridge({action:'openHjfyURL', paperId:'${pidAttr}'})` : '';

    menu.innerHTML = `
        <div class="ctx-item" onclick="openPaperDual('${pidAttr}', event)"><span>在新标签页打开论文</span><span>↩</span></div>
        <div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'openInNewWindow', paperId:'${pidAttr}'})"><span>在新窗口打开论文</span></div>
        <div class="ctx-sep"></div>
        <div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'importAttachment', paperId:'${pidAttr}'})"><span>导入附件…</span></div>
        <div class="ctx-item" onclick="closeContextMenu(); sendBridge({action:'importTranslatedPDF', paperId:'${pidAttr}'})"><span>导入中文 pdf…</span></div>
        <div class="ctx-sep"></div>
        <div class="ctx-item has-submenu">
            <span>将条目添加到分类</span><span class="ctx-arrow">▶</span>
            <div class="ctx-submenu">
                ${renderCategorySubmenu(p)}
            </div>
        </div>
        <div class="ctx-sep"></div>
        <div class="ctx-item ${arxivDisabled}" onclick="${arxivAction}"><span>跳转到 arXiv</span></div>
        <div class="ctx-item ${arxivDisabled}" onclick="${hjfyAction}"><span>跳转到幻觉翻译</span></div>
        <div class="ctx-sep"></div>
        <div class="ctx-item" onclick="closeContextMenu(); openEditMetaModal('${pidAttr}')"><span>编辑条目元数据…</span></div>
        <div class="ctx-sep"></div>
        <div class="ctx-item danger" onclick="closeContextMenu(); sendBridge({action:'deletePaper', paperId:'${pidAttr}'})"><span>删除条目…</span></div>
    `;
    menu.classList.add('open');
    const x = evt ? Math.min(evt.clientX, window.innerWidth - 240) : 200;
    const y = evt ? Math.min(evt.clientY, window.innerHeight - 340) : 200;
    menu.style.left = Math.max(8, x) + 'px';
    menu.style.top = Math.max(8, y) + 'px';
}

function closeContextMenu() {
    const menu = document.getElementById('ctxMenu');
    if (menu) menu.classList.remove('open');
}

window.openEditMetaModal = function(paperId) {
    const p = (state.papers || []).find(item => item.id === paperId);
    if (!p) return;
    const pidEl = document.getElementById('editPaperId');
    if (pidEl) pidEl.value = p.id;
    const tEl = document.getElementById('editTitle');
    if (tEl) tEl.value = p.title || '';
    const aEl = document.getElementById('editAuthors');
    if (aEl) aEl.value = p.authors || '';
    const yEl = document.getElementById('editYear');
    if (yEl) yEl.value = p.year || '';
    const vEl = document.getElementById('editVenue');
    if (vEl) vEl.value = p.venue || '';
    const xEl = document.getElementById('editArxivId');
    if (xEl) xEl.value = p.arxivId || '';
    const cEl = document.getElementById('editCategory');
    if (cEl) cEl.value = p.category || '';
    const tgEl = document.getElementById('editTags');
    if (tgEl) tgEl.value = (p.tags || []).join(', ');
    const modal = document.getElementById('editMetaModal');
    if (modal) modal.classList.add('open');
};

window.closeEditMetaModal = function() {
    const modal = document.getElementById('editMetaModal');
    if (modal) modal.classList.remove('open');
};

window.submitEditMetaModal = function() {
    const pidEl = document.getElementById('editPaperId');
    const paperId = pidEl ? pidEl.value : null;
    if (!paperId) return;
    const tEl = document.getElementById('editTitle');
    const aEl = document.getElementById('editAuthors');
    const yEl = document.getElementById('editYear');
    const vEl = document.getElementById('editVenue');
    const xEl = document.getElementById('editArxivId');
    const cEl = document.getElementById('editCategory');
    const tgEl = document.getElementById('editTags');
    const tagsStr = tgEl ? tgEl.value : '';
    const tags = tagsStr.split(/[,，]/).map(s => s.trim()).filter(Boolean);

    sendBridge({
        action: 'saveMetadata',
        paperId,
        title: tEl ? tEl.value : '',
        authors: aEl ? aEl.value : '',
        year: yEl ? yEl.value : '',
        venue: vEl ? vEl.value : '',
        arxivId: xEl ? xEl.value : '',
        category: cEl ? cEl.value : '',
        tags: tags
    });
    closeEditMetaModal();
};

window.triggerRefreshMetaInModal = function() {
    const pidEl = document.getElementById('editPaperId');
    const paperId = pidEl ? pidEl.value : null;
    if (!paperId) return;
    sendBridge({ action: 'refreshArxivMetadata', paperId });
    closeEditMetaModal();
};

function toggleSortDirection() {
    ui.sortAscending = !ui.sortAscending;
    renderCenter();
}

function sortByColumn(colKey) {
    if (ui.sortOrder === colKey) {
        ui.sortAscending = !ui.sortAscending;
    } else {
        ui.sortOrder = colKey;
        ui.sortAscending = (colKey === 'title' || colKey === 'authors' || colKey === 'status' || colKey === 'custom');
    }
    renderCenter();
}

function movePaperOrder(paperId, delta) {
    const currentList = getFilteredPapers();
    const idx = currentList.findIndex(p => p.id === paperId);
    if (idx < 0) return;
    const targetIdx = idx + delta;
    if (targetIdx < 0 || targetIdx >= currentList.length) return;
    const ids = currentList.map(p => p.id);
    const [moved] = ids.splice(idx, 1);
    ids.splice(targetIdx, 0, moved);
    ui.sortOrder = 'custom';
    ui.sortAscending = true;
    sendBridge({ action: 'reorderPapers', orderedIds: ids });
}

function handlePaperDragStart(paperId, evt) {
    draggedPaperId = paperId;
    if (evt && evt.dataTransfer) {
        evt.dataTransfer.effectAllowed = 'move';
        try { evt.dataTransfer.setData('text/plain', paperId); } catch (_) {}
    }
}

function handlePaperDragOver(targetPaperId, evt) {
    if (!draggedPaperId || draggedPaperId === targetPaperId) return;
    if (evt) {
        evt.preventDefault();
        if (evt.dataTransfer) evt.dataTransfer.dropEffect = 'move';
    }
}

function handlePaperDrop(targetPaperId, evt) {
    if (!draggedPaperId || draggedPaperId === targetPaperId) return;
    if (evt) {
        evt.preventDefault();
        evt.stopPropagation();
    }
    const currentList = getFilteredPapers();
    const fromIdx = currentList.findIndex(p => p.id === draggedPaperId);
    const toIdx = currentList.findIndex(p => p.id === targetPaperId);
    draggedPaperId = null;
    if (fromIdx < 0 || toIdx < 0) return;
    const ids = currentList.map(p => p.id);
    const [moved] = ids.splice(fromIdx, 1);
    ids.splice(toIdx, 0, moved);
    ui.sortOrder = 'custom';
    ui.sortAscending = true;
    sendBridge({ action: 'reorderPapers', orderedIds: ids });
}

function getFilteredPapers() {
    const papers = (state.papers || []).slice();
    let list = papers.filter(p => {
        if (ui.filterKind === 'recent') return !!p.lastOpenedTimestamp && p.lastOpenedTimestamp > p.addedTimestamp;
        if (ui.filterKind === 'favorites') return p.isFavorite;
        if (ui.filterKind.startsWith('status:')) return p.statusRaw === ui.filterKind.slice(7);
        if (ui.filterKind.startsWith('cat:')) return p.category === ui.filterKind.slice(4);
        return true;
    });

    if (ui.activeTag) {
        list = list.filter(p => (p.tags || []).includes(ui.activeTag) || p.category === ui.activeTag);
    }

    if (ui.searchQuery) {
        const q = ui.searchQuery.toLowerCase();
        list = list.filter(p =>
            p.title.toLowerCase().includes(q) ||
            p.authors.toLowerCase().includes(q) ||
            p.venue.toLowerCase().includes(q) ||
            p.category.toLowerCase().includes(q) ||
            (p.tags || []).some(t => t.toLowerCase().includes(q)) ||
            (p.annotations || []).some(a =>
                a.selectedText.toLowerCase().includes(q) ||
                a.markdownNote.toLowerCase().includes(q)
            ) ||
            (p.noteDocuments || []).some(nd =>
                nd.title.toLowerCase().includes(q) ||
                nd.markdownContent.toLowerCase().includes(q)
            )
        );
    }

    const statusRank = { 'unread': 0, 'reading': 1, 'completed': 2 };

    list.sort((a, b) => {
        let cmp = 0;
        if (ui.sortOrder === 'added') {
            cmp = a.addedTimestamp - b.addedTimestamp;
        } else if (ui.sortOrder === 'year') {
            cmp = (a.year + a.title).localeCompare(b.year + b.title, 'zh-CN', { numeric: true });
        } else if (ui.sortOrder === 'title') {
            cmp = a.title.localeCompare(b.title, 'zh-CN', { numeric: true });
        } else if (ui.sortOrder === 'authors') {
            cmp = (a.authors || '').localeCompare(b.authors || '', 'zh-CN');
        } else if (ui.sortOrder === 'notes') {
            const countA = (a.annotations ? a.annotations.length : 0) + (a.noteDocuments ? a.noteDocuments.length : 0);
            const countB = (b.annotations ? b.annotations.length : 0) + (b.noteDocuments ? b.noteDocuments.length : 0);
            cmp = countA - countB;
        } else if (ui.sortOrder === 'status') {
            cmp = (statusRank[a.statusRaw] ?? 9) - (statusRank[b.statusRaw] ?? 9);
        } else if (ui.sortOrder === 'custom') {
            const idxA = (a.customSortIndex !== null && a.customSortIndex !== undefined) ? a.customSortIndex : 999999;
            const idxB = (b.customSortIndex !== null && b.customSortIndex !== undefined) ? b.customSortIndex : 999999;
            cmp = idxA - idxB;
        } else {
            cmp = a.lastOpenedTimestamp - b.lastOpenedTimestamp;
        }
        if (cmp === 0) {
            cmp = a.title.localeCompare(b.title, 'zh-CN');
        }
        return ui.sortAscending ? cmp : -cmp;
    });
    return list;
}

function renderSidebar() {
    const childRowHTML = (kind, title, iconSVG) => `
        <div class="tree-row child ${ui.filterKind === kind ? 'active' : ''}" onclick="setFilter('${escapeJSAttr(kind)}', '${escapeJSAttr(title)}')">
            <span class="tree-icon">${iconSVG}</span>
            <span class="tree-label">${escapeHTML(title)}</span>
        </div>
    `;

    const catsHTML = (state.categories || []).map(cat => childRowHTML(
        'cat:' + cat,
        cat,
        `<svg width="18" height="18" viewBox="0 0 16 16" fill="none" stroke="#5B89C8" stroke-width="1.35" stroke-linejoin="round"><path d="M1.5 3.5A1.2 1.2 0 0 1 2.7 2.3h3.3l1.4 1.6h5.9a1.2 1.2 0 0 1 1.2 1.2v7.2a1.2 1.2 0 0 1-1.2 1.2H2.7a1.2 1.2 0 0 1-1.2-1.2V3.5z"/></svg>`
    )).join('');

    const childrenBlock = ui.treeExpanded ? `
        ${catsHTML}
        <div class="tree-row child" style="color:var(--accent); font-size:13px;" onclick="promptCreateNewCategory(event)">
            <span class="tree-icon" style="font-size:15px; font-weight:bold;">＋</span>
            <span class="tree-label">新建分类…</span>
        </div>
    ` : '';

    const totalCount = (state.papers || []).length;

    document.getElementById('sidebarScroll').innerHTML = `
        <div class="tree-row ${ui.filterKind === 'all' ? 'active' : ''}" onclick="setFilter('all', '我的文库')">
            <span class="tree-twisty" onclick="toggleRootTree(event)">${ui.treeExpanded ? '▾' : '▸'}</span>
            <span class="tree-icon">
                <svg width="19" height="19" viewBox="0 0 16 16" fill="none" stroke="#5A72C8" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round">
                    <path d="M2 6h12M3.2 6v6.5M6.4 6v6.5M9.6 6v6.5M12.8 6v6.5M1.5 12.8h13M8 2L1.5 6h13L8 2z"/>
                </svg>
            </span>
            <span class="tree-label">我的文库</span>
            <span style="font-size:12px; color:var(--text-tertiary); margin-left:auto;">${totalCount}</span>
        </div>
        ${childrenBlock}
    `;
}

function promptCreateNewCategory(evt) {
    if (evt) evt.stopPropagation();
    flushPendingMetadata();
    sendBridge({ action: 'createCategory' });
}

window.onCategoryCreated = function(category) {
    ui.treeExpanded = true;
    setFilter('cat:' + category, category);
};

function renderTagPanelOnly() {
    // Tag panel removed per user request for minimal unit library design
}

function renderCenter() {
    const centerEl = document.getElementById('centerContent');
    const filtered = getFilteredPapers();

    const titleEl = document.getElementById('currentViewTitle');
    const countEl = document.getElementById('currentViewCount');
    if (titleEl) titleEl.textContent = ui.filterTitle || '我的文库';
    if (countEl) countEl.textContent = `${filtered.length} 篇文献`;

    // Global Notes Stream if selected
    if (ui.filterKind === 'notes') {
        const allAnnots = [];
        (state.papers || []).forEach(p => {
            (p.annotations || []).forEach(a => allAnnots.push(a));
        });
        allAnnots.sort((a, b) => b.createdTimestamp - a.createdTimestamp);

        if (allAnnots.length === 0) {
            centerEl.innerHTML = `
                <div class="empty-box" style="margin:48px auto; max-width:400px; text-align:center;">
                    <h3 style="font-size:16px; margin-bottom:8px; color:var(--text-primary);">全局笔记流中暂无记录</h3>
                    <p style="font-size:13.5px; color:var(--text-secondary); line-height:1.5;">双击任意论文进入双栏对照阅读器，用鼠标划选正文即可添加多色高亮与精读笔记。</p>
                </div>
            `;
            return;
        }
        centerEl.innerHTML = `<div style="max-width:760px; margin:0 auto; padding:16px;">${allAnnots.map(a => renderNoteCardHTML(a, true)).join('')}</div>`;
        return;
    }

    if (filtered.length === 0) {
        centerEl.innerHTML = `
            <div class="empty-box" style="margin:54px auto; max-width:420px; text-align:center;">
                <h3 style="font-size:16px; margin-bottom:8px; color:var(--text-primary);">文库中暂无论文</h3>
                <p style="font-size:13.5px; color:var(--text-secondary); line-height:1.5;">点击上方「＋ 导入论文」或直接拖入 PDF 文件即可自动解析并开启双栏精读。</p>
            </div>
        `;
        return;
    }

    centerEl.innerHTML = renderZoteroTableHTML(filtered);
}

function renderZoteroTableHTML(list) {
    const docTypeIconSVG = `
        <svg width="19" height="19" viewBox="0 0 16 16" fill="none">
            <path d="M3 1.5h6.5l3 3v10H3v-13z" fill="#F8FAFC" stroke="#78869B" stroke-width="1.2"/>
            <path d="M9.5 1.5v3h3" stroke="#78869B" stroke-width="1.2"/>
            <path d="M5 6.2h5.5M5 8.5h5.5M5 10.8h3.5" stroke="#64748B" stroke-width="1.1" stroke-linecap="round"/>
            <circle cx="4.2" cy="11.5" r="2.1" fill="#E67E51"/>
        </svg>
    `;

    const pdfAttachmentIconSVG = `
        <svg width="18" height="18" viewBox="0 0 16 16" fill="none">
            <path d="M3.5 1.5h6l3 3v10h-9v-13z" fill="#FFF" stroke="#B0B7C3" stroke-width="1.15"/>
            <path d="M9.5 1.5v3h3" stroke="#B0B7C3" stroke-width="1.15"/>
            <rect x="4.5" y="7.2" width="6.5" height="3.8" rx="0.8" fill="#E05246"/>
        </svg>
    `;

    const rowsHTML = list.map(p => {
        const isSelected = (p.id === state.selectedPaperId);
        const isExpanded = !!ui.expandedPaperIds[p.id];
        const pidAttr = escapeJSAttr(p.id);
        const creatorText = formatZoteroCreator(p.authors);
        const hasAnyPDF = p.hasOriginal || p.hasTranslated || ((p.additionalPDFs || []).length > 0);
        const arxivBadge = p.arxivId ? `<span style="font-size:11px; padding:2px 6px; border-radius:4px; background:var(--bg-subtle); color:var(--text-secondary); margin-left:8px;">arXiv:${escapeHTML(p.arxivId)}</span>` : '';
        const yearText = p.year ? `<span style="font-size:12.5px; color:var(--text-tertiary); margin-left:6px;">(${escapeHTML(p.year)})</span>` : '';

        let subRows = '';
        if (isExpanded) {
            if (p.hasOriginal) {
                subRows += `
                <tr class="zotero-subrow" ondblclick="openPaperDual('${pidAttr}', event)" onclick="selectPaper('${pidAttr}')">
                    <td class="subrow-indent">${pdfAttachmentIconSVG} <span style="margin-left:6px;">原版 PDF (Original EN · ${p.origPages || 0} 页)</span></td>
                    <td></td>
                    <td class="row-attach-cell"></td>
                </tr>`;
            }
            if (p.hasTranslated) {
                subRows += `
                <tr class="zotero-subrow" ondblclick="openPaperDual('${pidAttr}', event)" onclick="selectPaper('${pidAttr}')">
                    <td class="subrow-indent">${pdfAttachmentIconSVG} <span style="margin-left:6px;">中文译版 PDF (Translated ZH · ${p.transPages || 0} 页)</span></td>
                    <td></td>
                    <td class="row-attach-cell"></td>
                </tr>`;
            }
            (p.additionalPDFs || []).forEach(ep => {
                subRows += `
                <tr class="zotero-subrow" ondblclick="openPaperDual('${pidAttr}', event)" onclick="selectPaper('${pidAttr}')">
                    <td class="subrow-indent">${pdfAttachmentIconSVG} <span style="margin-left:6px;">${escapeHTML(ep.title)}</span></td>
                    <td></td>
                    <td class="row-attach-cell"></td>
                </tr>`;
            });
        }

        return `
        <tr class="zotero-row ${isSelected ? 'selected' : ''}" draggable="true" ondragstart="handlePaperDragStart('${pidAttr}', event)" ondragover="handlePaperDragOver('${pidAttr}', event)" ondrop="handlePaperDrop('${pidAttr}', event)" data-paper-id="${escapeHTML(p.id)}" onclick="selectPaper('${pidAttr}')" ondblclick="openPaperDual('${pidAttr}', event)" oncontextmenu="openPaperContextMenu('${pidAttr}', event)">
            <td style="width:65%;">
                <div class="tbl-title-cell">
                    <span class="row-twisty" onclick="toggleRowExpand('${pidAttr}', event)">${isExpanded ? '▾' : '▸'}</span>
                    <span class="row-doc-icon">${docTypeIconSVG}</span>
                    <span class="row-title-text" style="font-weight:500; font-size:14.5px;" title="${escapeHTML(p.title)}">${escapeHTML(p.title)}</span>
                    ${yearText}
                    ${arxivBadge}
                </div>
            </td>
            <td style="width:28%; color:var(--text-secondary); font-size:13.5px;" title="${escapeHTML(p.authors || '')}">${escapeHTML(creatorText)}</td>
            <td class="row-attach-cell" style="width:7%;">
                ${hasAnyPDF ? `<span class="row-pdf-badge" onclick="openPaperDual('${pidAttr}', event)" title="双击或点击打开双栏 PDF 阅读器">${pdfAttachmentIconSVG}</span>` : ''}
            </td>
        </tr>
        ${subRows}
        `;
    }).join('');

    return `
    <div class="zotero-table-wrap">
        <table class="zotero-table">
            <tbody>${rowsHTML}</tbody>
        </table>
    </div>
    `;
}

function renderInspector() {
    const headerEl = document.getElementById('inspectorHeader');
    const bodyEl = document.getElementById('inspectorBody');
    if (!bodyEl) return;
    const filteredCount = getFilteredPapers().length;
    const p = (state.papers || []).find(item => item.id === state.selectedPaperId);

    // Summary State ("此视图中有 N 个条目") when no item detail is open
    if (ui.inspectorShowingSummary || !p) {
        bodyEl.dataset.inspPaperId = '';
        if (headerEl) headerEl.style.display = 'none';
        bodyEl.innerHTML = `<div class="inspector-summary-placeholder">此视图中有 ${filteredCount} 个条目</div>`;
        syncDropSlotRects();
        return;
    }

    if (headerEl) headerEl.style.display = 'flex';
    const totalNotes = paperTotalNoteCount(p);
    document.getElementById('inspNoteCount').textContent = totalNotes > 0 ? `(${totalNotes})` : '';
    const totalRels = p.relatedPapers.length + p.resources.length;
    document.getElementById('inspRelCount').textContent = totalRels > 0 ? `(${totalRels})` : '';

    // CRITICAL: If user is actively editing a metadata input for THIS paper (or IME composing),
    // update non-input elements in place and NEVER destroy/recreate the focused input DOM node!
    const activeEl = document.activeElement;
    const isEditingCurrentPaperMeta = (
        ui.inspectorTab === 0 &&
        bodyEl.dataset.inspPaperId === p.id &&
        ((activeEl && activeEl.classList && activeEl.classList.contains('meta-input')) ||
         (pendingMetadata && pendingMetadata.paperId === p.id) ||
         isComposingMeta)
    );

    if (isEditingCurrentPaperMeta) {
        const headerTitleEl = document.getElementById('inspHeaderTitle');
        if (headerTitleEl) headerTitleEl.textContent = p.title;
        syncDropSlotRects();
        return;
    }

    bodyEl.dataset.inspPaperId = p.id;
    if (ui.inspectorTab === 0) {
        renderInspectorInfoTab(bodyEl, p);
    } else if (ui.inspectorTab === 1) {
        renderInspectorNotesTab(bodyEl, p);
    } else {
        renderInspectorRelatedTab(bodyEl, p);
    }

    syncDropSlotRects();
}

function renderInspectorInfoTab(bodyEl, p) {
    const origSizeStr = formatFileSize(p.origSizeKB);
    const transSizeStr = formatFileSize(p.transSizeKB);
    const origMeta = p.hasOriginal ? `${p.origPages} 页${origSizeStr ? ' · ' + origSizeStr : ''}` : '未绑定 · 可拖入';
    const transMeta = p.hasTranslated ? `${p.transPages} 页${transSizeStr ? ' · ' + transSizeStr : ''}` : '未绑定 · 可拖入';
    const pidAttr = escapeJSAttr(p.id);
    const extraPDFs = p.additionalPDFs || [];
    const extraPDFsHTML = extraPDFs.map(ep => `
        <div class="rel-item-card" style="margin-top:6px;">
            <div class="rel-item-main" onclick="openPaperDual('${pidAttr}', event)">
                <div class="rel-item-title">📄 ${escapeHTML(ep.title)}</div>
                <div class="rel-item-sub">附加 PDF · 可在阅读器切换</div>
            </div>
            <button class="btn-secondary" style="height:26px;padding:0 8px;font-size:12px;color:var(--danger);" onclick="sendBridge({action:'removeAdditionalPDF', paperId:'${pidAttr}', pdfId:'${escapeJSAttr(ep.id)}'})">✕</button>
        </div>
    `).join('');

    bodyEl.innerHTML = `
        <h2 class="insp-paper-title selectable" id="inspHeaderTitle">${escapeHTML(p.title)}</h2>
        <div class="insp-hero-bar">
            <button class="btn-hero-read" onclick="openPaperDual('${pidAttr}', event)">
                中英双栏打开
            </button>
            <button class="btn-secondary" style="height:34px;padding:0 12px;font-size:13.5px;font-weight:600;" onclick="sendBridge({action:'openPaperNotesSidebar', paperId:'${pidAttr}'})" title="打开阅读器，在右侧边栏编辑和预览笔记">
                右侧笔记
            </button>
            <button class="btn-secondary btn-icon" style="height:34px;width:34px;font-size:16px;color:${p.isFavorite ? '#f59e0b' : 'var(--text-tertiary)'};" onclick="toggleStar('${pidAttr}', event)" title="切换星标收藏">★</button>
        </div>

        <div class="seg-group" style="width:100%; display:grid; grid-template-columns:1fr 1fr 1fr; margin-bottom:10px;">
            <button class="seg-btn ${p.statusRaw === 'unread' ? 'active' : ''}" style="justify-content:center;" onclick="sendBridge({action:'updateStatus', paperId:'${pidAttr}', status:'unread'})">未读</button>
            <button class="seg-btn ${p.statusRaw === 'reading' ? 'active' : ''}" style="justify-content:center;" onclick="sendBridge({action:'updateStatus', paperId:'${pidAttr}', status:'reading'})">正在精读</button>
            <button class="seg-btn ${p.statusRaw === 'completed' ? 'active' : ''}" style="justify-content:center;" onclick="sendBridge({action:'updateStatus', paperId:'${pidAttr}', status:'completed'})">已精读</button>
        </div>

        <div class="insp-section-title">
            <span>▾ 条目信息</span>
            <div style="display:flex;gap:6px;">
                <button class="tag-clear-btn" onclick="sendBridge({action:'refreshArxivMetadata', paperId:'${pidAttr}'})" title="重新从 Semantic Scholar 与 arXiv 拉取官方元数据与引用数">↻ 刷新元数据</button>
                <button class="tag-clear-btn" onclick="sendBridge({action:'autoExtractMetadata', paperId:'${pidAttr}'})" title="从 PDF 首页智能提取标题、作者与年份">本地识别</button>
            </div>
        </div>
        <div class="meta-card">
            <div class="meta-row">
                <span class="meta-key">条目类型</span>
                <div style="font-size:13.5px;padding:4px 6px;color:var(--text-secondary);display:flex;align-items:center;gap:8px;">
                    <span>期刊论文 / 预印本</span>
                    ${p.citationCount != null ? `<span class="citation-badge">引用数: ${p.citationCount.toLocaleString()} 次</span>` : ''}
                </div>
            </div>
            <div class="meta-row">
                <span class="meta-key">标题</span>
                <input class="meta-input" id="inspTitle" value="${escapeHTML(p.title)}" oncompositionstart="isComposingMeta=true" oncompositionend="isComposingMeta=false; scheduleSaveInspMeta('${pidAttr}')" oninput="scheduleSaveInspMeta('${pidAttr}')" onchange="saveInspMeta('${pidAttr}')">
            </div>
            <div class="meta-row">
                <span class="meta-key">创建者</span>
                <input class="meta-input" id="inspAuthors" value="${escapeHTML(p.authors)}" placeholder="作者姓名" oncompositionstart="isComposingMeta=true" oncompositionend="isComposingMeta=false; scheduleSaveInspMeta('${pidAttr}')" oninput="scheduleSaveInspMeta('${pidAttr}')" onchange="saveInspMeta('${pidAttr}')">
            </div>
            <div class="meta-row">
                <span class="meta-key">发表年份</span>
                <input class="meta-input" id="inspYear" value="${escapeHTML(p.year)}" oncompositionstart="isComposingMeta=true" oncompositionend="isComposingMeta=false; scheduleSaveInspMeta('${pidAttr}')" oninput="scheduleSaveInspMeta('${pidAttr}')" onchange="saveInspMeta('${pidAttr}')">
            </div>
            <div class="meta-row">
                <span class="meta-key">出版来源</span>
                <input class="meta-input" id="inspVenue" value="${escapeHTML(p.venue)}" placeholder="arXiv / NeurIPS / ACL" oncompositionstart="isComposingMeta=true" oncompositionend="isComposingMeta=false; scheduleSaveInspMeta('${pidAttr}')" oninput="scheduleSaveInspMeta('${pidAttr}')" onchange="saveInspMeta('${pidAttr}')">
            </div>
            <div class="meta-row">
                <span class="meta-key">arXiv ID</span>
                <div style="display:flex;align-items:center;gap:6px;flex:1;min-width:0;">
                    <input class="meta-input" id="inspArxivId" value="${escapeHTML(p.arxivId || '')}" placeholder="例如：1706.03762v7" oncompositionstart="isComposingMeta=true" oncompositionend="isComposingMeta=false; scheduleSaveInspMeta('${pidAttr}')" oninput="scheduleSaveInspMeta('${pidAttr}')" onchange="saveInspMeta('${pidAttr}')">
                    ${p.arxivId ? `<a class="arxiv-badge-link" href="#" onclick="sendBridge({action:'openArxivURL', paperId:'${pidAttr}'}); return false;" title="在浏览器打开 arXiv 页面">arXiv ↗</a><a class="arxiv-badge-link" style="background:rgba(245,158,11,0.12);color:#d97706;" href="#" onclick="sendBridge({action:'openHjfyURL', paperId:'${pidAttr}'}); return false;" title="在浏览器打开幻觉翻译">幻觉翻译 ↗</a>` : ''}
                </div>
            </div>
            <div class="meta-row">
                <span class="meta-key">分类合集</span>
                <input class="meta-input" id="inspCategory" value="${escapeHTML(p.category)}" oncompositionstart="isComposingMeta=true" oncompositionend="isComposingMeta=false; scheduleSaveInspMeta('${pidAttr}')" oninput="scheduleSaveInspMeta('${pidAttr}')" onchange="saveInspMeta('${pidAttr}')">
            </div>
            <div class="meta-row">
                <span class="meta-key">标签</span>
                <input class="meta-input" id="inspTags" value="${escapeHTML((p.tags || []).join(', '))}" placeholder="用逗号分隔，如: MoE, RL" oncompositionstart="isComposingMeta=true" oncompositionend="isComposingMeta=false; scheduleSaveInspMeta('${pidAttr}')" oninput="scheduleSaveInspMeta('${pidAttr}')" onchange="saveInspMeta('${pidAttr}')">
            </div>
        </div>

        <div class="insp-section-title">
            <span>▾ 附件 (PDF 文档)</span>
            <button class="tag-clear-btn" onclick="sendBridge({action:'addAdditionalPDF', paperId:'${pidAttr}'})">＋ 添加 PDF</button>
        </div>
        <div class="pdf-slots-grid">
            <div class="pdf-slot-card" id="slotOriginal">
                <div class="pdf-slot-top">
                    <div class="pdf-slot-thumb">
                        ${p.origThumb ? `<img src="${p.origThumb}" alt="">` : 'EN'}
                    </div>
                    <div style="min-width:0;">
                        <div class="pdf-slot-label">原版 PDF</div>
                        <div class="pdf-slot-meta ${p.hasOriginal ? '' : 'missing'}">${origMeta}</div>
                    </div>
                </div>
                <button class="btn-secondary" style="width:100%;justify-content:center;height:28px;font-size:12.5px;" onclick="sendBridge({action:'importOrReplacePDF', paperId:'${pidAttr}', side:'original'})">
                    ${p.hasOriginal ? '替换文件…' : '＋ 导入原版…'}
                </button>
            </div>

            <div class="pdf-slot-card" id="slotTranslated">
                <div class="pdf-slot-top">
                    <div class="pdf-slot-thumb">
                        ${p.transThumb ? `<img src="${p.transThumb}" alt="">` : 'ZH'}
                    </div>
                    <div style="min-width:0;">
                        <div class="pdf-slot-label">中文译版</div>
                        <div class="pdf-slot-meta ${p.hasTranslated ? '' : 'missing'}">${transMeta}</div>
                    </div>
                </div>
                <button class="btn-secondary" style="width:100%;justify-content:center;height:28px;font-size:12.5px;" onclick="sendBridge({action:'importOrReplacePDF', paperId:'${pidAttr}', side:'translated'})">
                    ${p.hasTranslated ? '替换文件…' : '＋ 导入译版…'}
                </button>
            </div>
        </div>
        ${extraPDFsHTML}

        <div style="display:flex; gap:6px; margin-top:14px; flex-wrap:wrap;">
            <button class="btn-secondary" style="flex:1;justify-content:center;font-size:12.5px;height:30px;" onclick="sendBridge({action:'revealFolder', paperId:'${pidAttr}'})">打开目录</button>
            <button class="btn-secondary" style="flex:1;justify-content:center;font-size:12.5px;height:30px;" onclick="sendBridge({action:'revealMarkdown', paperId:'${pidAttr}'})">定位 notes.md</button>
            <button class="btn-secondary" style="color:var(--danger);font-size:12.5px;height:30px;padding:0 12px;" onclick="sendBridge({action:'deletePaper', paperId:'${pidAttr}'})" title="从文献库移除">移除</button>
        </div>
    `;
}

function readInspectorMetadata(paperId) {
    if (paperId !== state.selectedPaperId) return null;
    const title = document.getElementById('inspTitle');
    if (!title) return null;
    const arxivInput = document.getElementById('inspArxivId');
    return {
        action: 'saveMetadata', paperId, title: title.value,
        authors: document.getElementById('inspAuthors').value,
        year: document.getElementById('inspYear').value,
        venue: document.getElementById('inspVenue').value,
        category: document.getElementById('inspCategory').value,
        tags: document.getElementById('inspTags').value,
        arxivId: arxivInput ? arxivInput.value : ''
    };
}

function flushPendingMetadata() {
    if (typeof isComposingMeta !== 'undefined' && isComposingMeta) return;
    if (metaSaveTimer) clearTimeout(metaSaveTimer);
    metaSaveTimer = null;
    const payload = pendingMetadata;
    pendingMetadata = null;
    if (payload) sendBridge(payload);
}

function scheduleSaveInspMeta(paperId) {
    if (typeof isComposingMeta !== 'undefined' && isComposingMeta) return;
    const titleEl = document.getElementById('inspTitle');
    const headerTitleEl = document.getElementById('inspHeaderTitle');
    if (titleEl && headerTitleEl && titleEl.value && typeof titleEl.value.trim === 'function' && titleEl.value.trim()) {
        headerTitleEl.textContent = titleEl.value.trim();
    }
    pendingMetadata = readInspectorMetadata(paperId);
    if (metaSaveTimer) clearTimeout(metaSaveTimer);
    metaSaveTimer = setTimeout(flushPendingMetadata, 500);
}

function saveInspMeta(paperId) {
    if (typeof isComposingMeta !== 'undefined') isComposingMeta = false;
    const payload = readInspectorMetadata(paperId);
    if (payload) pendingMetadata = payload;
    flushPendingMetadata();
}

function renderNoteCardHTML(n, showPaperHeader) {
    const bodyHTML = renderMarkdownWithMath(n.markdownNote);
    const nidAttr = escapeJSAttr(n.id);
    const paperHeader = showPaperHeader ? `
        <div style="font-size:12.5px;font-weight:600;color:var(--text-secondary);margin-bottom:6px;padding-bottom:5px;border-bottom:1px dashed var(--border-hairline);cursor:pointer;" onclick="sendBridge({action:'noteJump', annotId:'${nidAttr}'})">
            📄 ${escapeHTML(n.paperTitle)}
        </div>
    ` : '';
    const linkHTML = n.linkedURL ? `
        <div style="margin-top:6px;">
            <span class="chip" style="background:var(--accent-soft);color:var(--accent);cursor:pointer;" onclick="sendBridge({action:'noteOpenLink', annotId:'${nidAttr}'})">
                🔗 ${escapeHTML(n.linkedTitle || n.linkedURL)}
            </span>
        </div>
    ` : '';

    return `
    <div class="note-card">
        ${paperHeader}
        <div class="note-card-header">
            <div class="note-badge-group" onclick="sendBridge({action:'noteJump', annotId:'${nidAttr}'})" title="点击跳转到 PDF 对应高亮位置">
                <span class="color-dot" style="background:${n.colorHex}"></span>
                <span class="note-page-pill">${escapeHTML(n.sideBadge)} · P.${n.pageNumber}</span>
            </div>
            <div style="display:flex;gap:5px;">
                <button class="btn-secondary" style="height:26px;padding:0 9px;font-size:12px;" onclick="sendBridge({action:'noteEdit', annotId:'${nidAttr}'})">编辑</button>
                <button class="btn-secondary" style="height:26px;padding:0 9px;font-size:12px;color:var(--danger);" onclick="sendBridge({action:'noteDelete', annotId:'${nidAttr}'})">删除</button>
            </div>
        </div>
        <div class="note-excerpt" style="border-left-color:${n.colorHex}" onclick="sendBridge({action:'noteJump', annotId:'${nidAttr}'})">
            “${escapeHTML(n.selectedText)}”
        </div>
        ${bodyHTML ? `<div class="md-body selectable">${bodyHTML}</div>` : ''}
        ${linkHTML}
    </div>
    `;
}

function renderInspectorNotesTab(bodyEl, p) {
    const notes = (p.annotations || []).slice();
    const noteDocs = p.noteDocuments || [];
    const pidAttr = escapeJSAttr(p.id);

    notes.sort((a, b) => {
        if (ui.noteSortOrder === 'newest') return b.createdTimestamp - a.createdTimestamp;
        if (ui.noteSortOrder === 'oldest') return a.createdTimestamp - b.createdTimestamp;
        if (ui.noteSortOrder === 'color') return a.colorHex.localeCompare(b.colorHex);
        if (a.pageNumber !== b.pageNumber) return a.pageNumber - b.pageNumber;
        return a.createdTimestamp - b.createdTimestamp;
    });

    const noteDocsHTML = noteDocs.map(nd => `
        <div class="note-card" style="border-left:3px solid var(--accent);">
            <div class="note-card-header">
                <span class="note-page-pill">📝 ${escapeHTML(nd.title)}</span>
                <button class="btn-secondary" style="height:26px;padding:0 9px;font-size:12px;" onclick="sendBridge({action:'openPaperNotesSidebar', paperId:'${pidAttr}'})">打开右侧笔记</button>
            </div>
            <div class="md-body selectable">${renderMarkdownWithMath(nd.markdownContent)}</div>
        </div>
    `).join('');

    if (notes.length === 0 && noteDocs.length === 0) {
        bodyEl.innerHTML = `
            <div style="text-align:center;padding:36px 14px;color:var(--text-secondary);">
                <div style="font-size:14.5px;font-weight:600;margin-bottom:6px;">该论文暂无高亮或精读笔记</div>
                <div style="font-size:13px;color:var(--text-tertiary);line-height:1.6;margin-bottom:14px;">论文笔记统一在阅读器右侧边栏编辑；划选 PDF 文字后点击「引用笔记」，即可添加返回原文的链接。</div>
                <div style="display:flex;justify-content:center;gap:8px;">
                    <button class="btn-primary" onclick="sendBridge({action:'openPaperNotesSidebar', paperId:'${pidAttr}'})">打开右侧笔记</button>
                    <button class="btn-secondary" onclick="openPaperDual('${pidAttr}', event)">中英双栏打开</button>
                </div>
            </div>
        `;
        return;
    }
    bodyEl.innerHTML = `
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;gap:6px;">
            <span style="font-size:13px;font-weight:600;color:var(--text-secondary);">${noteDocs.length} 篇笔记 · ${notes.length} 条高亮</span>
            <div style="display:flex;gap:5px;align-items:center;">
                <button class="btn-secondary" style="height:26px;font-size:12px;" onclick="sendBridge({action:'openPaperNotesSidebar', paperId:'${pidAttr}'})">右侧笔记</button>
                <button class="btn-secondary" style="height:26px;font-size:12px;" onclick="sendBridge({action:'revealMarkdown', paperId:'${pidAttr}'})">notes.md</button>
            </div>
        </div>
        ${noteDocsHTML}
        ${notes.map(n => renderNoteCardHTML(n, false)).join('')}
    `;
}

function renderInspectorRelatedTab(bodyEl, p) {
    const otherPapers = (state.papers || []).filter(item => item.id !== p.id);
    const pidAttr = escapeJSAttr(p.id);
    const relRows = (p.relatedPapers || []).map(rel => `
        <div class="rel-item-card">
            <div class="rel-item-main" onclick="openPaperDual('${escapeJSAttr(rel.targetPaperId)}', event)">
                <div class="rel-item-title">📄 ${escapeHTML(rel.targetTitle)}</div>
                <div class="rel-item-sub">${escapeHTML(rel.relationNote || '双向关联论文')}</div>
            </div>
            <button class="btn-secondary" style="height:26px;padding:0 8px;font-size:12px;" onclick="sendBridge({action:'unlinkRelatedPaper', paperId:'${pidAttr}', targetPaperId:'${escapeJSAttr(rel.targetPaperId)}'})">解除</button>
        </div>
    `).join('');

    const addRelBox = otherPapers.length > 0 ? `
        <div style="background:var(--bg-surface);border:1px solid var(--border-hairline);border-radius:8px;padding:10px;margin-top:8px;">
            <select id="relTargetSelect" class="form-control" style="height:30px;font-size:13px;margin-bottom:8px;">
                ${otherPapers.map(op => `<option value="${escapeHTML(op.id)}">${escapeHTML(op.title)}</option>`).join('')}
            </select>
            <div style="display:flex;gap:6px;">
                <input id="relNoteInput" class="form-control" style="height:30px;font-size:13px;" placeholder="关联备注 (如: 基线模型)">
                <button class="btn-primary" style="height:30px;font-size:13px;" onclick="submitLinkRelated('${pidAttr}')">＋ 关联</button>
            </div>
        </div>
    ` : `<div style="font-size:13px;color:var(--text-tertiary);">导入更多论文后可在此建立双向关联</div>`;

    const resRows = (p.resources || []).map(res => `
        <div class="rel-item-card">
            <div class="rel-item-main" onclick="sendBridge({action:'openResource', urlOrPath:'${escapeJSAttr(res.urlOrPath)}'})">
                <div class="rel-item-title">${res.isLocalFile ? '📎' : '🔗'} ${escapeHTML(res.title)}</div>
                <div class="rel-item-sub">${escapeHTML(res.urlOrPath)}</div>
            </div>
            <button class="btn-secondary" style="height:26px;padding:0 8px;font-size:12px;color:var(--danger);" onclick="sendBridge({action:'deleteResource', paperId:'${pidAttr}', resourceId:'${escapeJSAttr(res.id)}'})">✕</button>
        </div>
    `).join('');

    bodyEl.innerHTML = `
        <div class="insp-section-title" style="margin-top:0;">
            <span>▾ 相关条目 (${(p.relatedPapers || []).length})</span>
        </div>
        ${relRows || `<div style="font-size:13px;color:var(--text-secondary);margin-bottom:6px;">暂无关联论文</div>`}
        ${addRelBox}

        <div class="insp-section-title">
            <span>▾ 外部链接与附件 (${(p.resources || []).length})</span>
        </div>
        ${resRows || `<div style="font-size:13px;color:var(--text-secondary);margin-bottom:8px;">暂无挂载链接或文件</div>`}

        <div style="background:var(--bg-surface);border:1px solid var(--border-hairline);border-radius:8px;padding:10px;margin-top:8px;">
            <input id="webTitleInput" class="form-control" style="height:30px;font-size:13px;margin-bottom:8px;" placeholder="链接名称 (如: GitHub 官方代码库)">
            <div style="display:flex;gap:6px;margin-bottom:8px;">
                <input id="webURLInput" class="form-control" style="height:30px;font-size:13px;" placeholder="https://github.com/...">
                <button class="btn-primary" style="height:30px;font-size:13px;" onclick="submitAddWebLink('${pidAttr}')">＋ 绑定</button>
            </div>
            <button class="btn-secondary" style="width:100%;justify-content:center;height:30px;font-size:13px;" onclick="sendBridge({action:'addLocalAttachment', paperId:'${pidAttr}'})">挂载本地文件 / 补充材料…</button>
        </div>
    `;
}

function submitLinkRelated(paperId) {
    const sel = document.getElementById('relTargetSelect');
    const note = document.getElementById('relNoteInput');
    if (sel && sel.value) {
        sendBridge({
            action: 'linkRelatedPaper',
            paperId,
            targetPaperId: sel.value,
            relationNote: note ? note.value : ''
        });
    }
}

function submitAddWebLink(paperId) {
    const t = document.getElementById('webTitleInput');
    const u = document.getElementById('webURLInput');
    if (u && u.value.trim()) {
        sendBridge({
            action: 'addWebResource',
            paperId,
            title: t ? t.value : '',
            url: u.value.trim()
        });
    }
}

function renderAll() {
    renderSidebar();
    renderCenter();
    renderInspector();
}

document.getElementById('searchInput').addEventListener('input', (e) => {
    ui.searchQuery = e.target.value.trim();
    renderCenter();
    if (ui.inspectorShowingSummary) renderInspector();
});
const inspBody = document.getElementById('inspectorBody');
if (inspBody) {
    inspBody.addEventListener('scroll', () => {
        syncDropSlotRects();
    });
}
window.addEventListener('resize', () => {
    syncDropSlotRects();
});
document.addEventListener('click', () => {
    closeContextMenu();
});
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        closeCreatePaperModal();
        closeEditMetaModal();
        closeContextMenu();
        return;
    }
    const tag = (e.target && e.target.tagName) ? e.target.tagName.toLowerCase() : '';
    if (tag === 'input' || tag === 'textarea' || tag === 'select') return;
    if (document.getElementById('createModal').classList.contains('open')) return;
    if (document.getElementById('editMetaModal') && document.getElementById('editMetaModal').classList.contains('open')) return;

    if (e.key === 'Enter' && state.selectedPaperId) {
        e.preventDefault();
        openPaperDual(state.selectedPaperId, e);
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowRight' || e.key === 'ArrowUp' || e.key === 'ArrowLeft') {
        const list = getFilteredPapers();
        if (list.length === 0) return;
        e.preventDefault();
        const curIdx = list.findIndex(item => item.id === state.selectedPaperId);
        const delta = (e.key === 'ArrowDown' || e.key === 'ArrowRight') ? 1 : -1;
        const nextIdx = curIdx < 0 ? 0 : (curIdx + delta + list.length) % list.length;
        selectPaper(list[nextIdx].id, false);
    }
});

renderAll();
