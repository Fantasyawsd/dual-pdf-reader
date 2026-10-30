    function escapeHTML(str) {
        return (str || '').replace(/&/g, '&amp;')
                          .replace(/</g, '&lt;')
                          .replace(/>/g, '&gt;')
                          .replace(/"/g, '&quot;');
    }

    // 内置零依赖离线 LaTeX 公式转高颜值排版 HTML 引擎
    function renderLatexFormula(tex, isBlock) {
        let s = escapeHTML(tex.trim());

        // 1. 解析矩阵与分段函数环境 (pmatrix, bmatrix, vmatrix, matrix, cases)，将其转换为无花括号的 HTML 结构以兼容外层嵌套分式
        s = s.replace(/\\begin\{(pmatrix|bmatrix|vmatrix|matrix|cases)\}([\s\S]*?)\\end\{\1\}/g, (_, env, body) => {
            let leftDelim = '';
            let rightDelim = '';
            if (env === 'pmatrix') { leftDelim = '('; rightDelim = ')'; }
            else if (env === 'bmatrix') { leftDelim = '['; rightDelim = ']'; }
            else if (env === 'vmatrix') { leftDelim = '|'; rightDelim = '|'; }
            else if (env === 'cases') { leftDelim = '{'; rightDelim = ''; }

            const rows = body.trim().split(/\\\\/).map(r => r.trim()).filter(r => r.length > 0);
            const rowsHTML = rows.map(rowStr => {
                const cells = rowStr.split(/&amp;/).map(c => c.trim());
                return `<span class="m-row">${cells.map(c => `<span class="m-cell">${c}</span>`).join('')}</span>`;
            }).join('');

            const lSpan = leftDelim ? `<span class="m-delim">${leftDelim}</span>` : '';
            const rSpan = rightDelim ? `<span class="m-delim">${rightDelim}</span>` : '';
            return `<span class="math-matrix">${lSpan}<span class="m-table">${rowsHTML}</span>${rSpan}</span>`;
        });

        // 清理其余环境与定界修饰符 \left / \right
        s = s.replace(/\\begin\{(aligned|align\*|align)\}/g, '');
        s = s.replace(/\\end\{(aligned|align\*|align)\}/g, '');
        s = s.replace(/\\left\s*\\\{/g, '{').replace(/\\right\s*\\\}/g, '}');
        s = s.replace(/\\left\s*\./g, '').replace(/\\right\s*\./g, '');
        s = s.replace(/\\left\s*([\(\[\|])/g, '$1').replace(/\\right\s*([\)\]\|])/g, '$1');
        s = s.replace(/\\left/g, '').replace(/\\right/g, '');
        s = s.replace(/\\\{/g, '{').replace(/\\\}/g, '}');
        s = s.replace(/\\%/g, '%');
        s = s.replace(/\\\\/g, '<br>');
        s = s.replace(/&amp;/g, ' ');

        // 2. 处理字体样式与重音符号 (在分式和上下标之前执行，避免内部花括号干扰分式匹配)
        s = s.replace(/\\(text|mathrm|operatorname)\{([^{}]+)\}/g, '<span class="math-op">$2</span>');
        s = s.replace(/\\(mathbf|boldsymbol|textbf)\{([^{}]+)\}/g, '<b>$2</b>');
        s = s.replace(/\\mathit\{([^{}]+)\}/g, '<i>$1</i>');

        const bbMap = {
            'R': 'ℝ', 'E': '𝔼', 'N': 'ℕ', 'Z': 'ℤ', 'Q': 'ℚ', 'P': 'ℙ', 'C': 'ℂ', 'I': '𝕀'
        };
        s = s.replace(/\\mathbb\{([A-Z])\}/g, (_, ch) => `<span class="math-op">${bbMap[ch] || ch}</span>`);

        const calMap = {
            'L': 'ℒ', 'O': '𝒪', 'D': '𝒟', 'N': '𝒩', 'H': 'ℋ', 'F': 'ℱ', 'E': 'ℰ', 'M': 'ℳ', 'B': 'ℬ', 'R': 'ℛ'
        };
        s = s.replace(/\\mathcal\{([A-Z])\}/g, (_, ch) => calMap[ch] ? `<span class="math-op">${calMap[ch]}</span>` : `<span class="math-cal">${ch}</span>`);

        // 重音帽子符号 \hat{x}, \bar{x}, \tilde{x}, \vec{x}, \dot{x}
        s = s.replace(/\\hat\{([^{}]+)\}/g, '$1&#770;');
        s = s.replace(/\\bar\{([^{}]+)\}/g, '$1&#772;');
        s = s.replace(/\\overline\{([^{}]+)\}/g, '<span style="text-decoration:overline">$1</span>');
        s = s.replace(/\\tilde\{([^{}]+)\}/g, '$1&#771;');
        s = s.replace(/\\vec\{([^{}]+)\}/g, '$1&#8407;');
        s = s.replace(/\\dot\{([^{}]+)\}/g, '$1&#775;');

        // 3. 处理大型算子 \sum_{a}^{b}, \prod_{a}^{b}, \int_{a}^{b}
        s = s.replace(/\\(sum|prod|int)_\{([^{}]+)\}\^\{([^{}]+)\}/g, (_, op, sub, sup) => {
            const sym = op === 'sum' ? '∑' : (op === 'prod' ? '∏' : '∫');
            return `<span class="sum-op"><span class="sup">${sup}</span><span class="sym">${sym}</span><span class="sub">${sub}</span></span>`;
        });
        s = s.replace(/\\(sum|prod|int)_([a-zA-Z0-9])\^([a-zA-Z0-9])/g, (_, op, sub, sup) => {
            const sym = op === 'sum' ? '∑' : (op === 'prod' ? '∏' : '∫');
            return `<span class="sum-op"><span class="sup">${sup}</span><span class="sym">${sym}</span><span class="sub">${sub}</span></span>`;
        });
        s = s.replace(/\\(sum|prod|int)_\{([^{}]+)\}/g, (_, op, sub) => {
            const sym = op === 'sum' ? '∑' : (op === 'prod' ? '∏' : '∫');
            return `<span class="sum-op"><span class="sym">${sym}</span><span class="sub">${sub}</span></span>`;
        });
        s = s.replace(/\\sum/g, '∑').replace(/\\prod/g, '∏').replace(/\\int/g, '∫');

        // 4. 交替迭代转换上下标 _{...} / ^{...}、根号 \sqrt{...} 与多层嵌套分式 \frac{a}{b} (支持 4 层深度)
        for (let i = 0; i < 4; i++) {
            s = s.replace(/_\{([^{}]+)\}/g, '<sub>$1</sub>');
            s = s.replace(/\^\{([^{}]+)\}/g, '<sup>$1</sup>');
            s = s.replace(/\\sqrt\{([^{}]+)\}/g, '√<span style="text-decoration:overline">$1</span>');
            s = s.replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g,
                '<span class="frac"><span>$1</span><span>$2</span></span>');
        }

        // 5. 常用数学函数与希腊字母符号映射
        const mathFuncs = ['softmax', 'argmax', 'argmin', 'max', 'min', 'sup', 'inf', 'lim', 'log', 'ln', 'exp', 'sin', 'cos', 'tan', 'tanh', 'det', 'dim', 'KL', 'CE', 'MSE'];
        for (const fn of mathFuncs) {
            s = s.replace(new RegExp('\\\\' + fn + '\\b', 'g'), `<span class="math-op">${fn}</span>`);
        }

        const symbols = {
            'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ',
            'epsilon': 'ϵ', 'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
            'theta': 'θ', 'vartheta': 'ϑ', 'iota': 'ι', 'kappa': 'κ',
            'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π',
            'rho': 'ρ', 'sigma': 'σ', 'tau': 'τ', 'upsilon': 'υ',
            'phi': 'ϕ', 'varphi': 'φ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
            'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ',
            'Xi': 'Ξ', 'Pi': 'Π', 'Sigma': 'Σ', 'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω',
            'times': '×', 'cdot': '·', 'cdots': '⋯', 'ldots': '…', 'dots': '…',
            'leq': '≤', 'le': '≤', 'geq': '≥', 'ge': '≥',
            'neq': '≠', 'ne': '≠', 'approx': '≈', 'equiv': '≡', 'sim': '∼', 'simeq': '≃', 'propto': '∝',
            'll': '≪', 'gg': '≫', 'infty': '∞',
            'rightarrow': '→', 'to': '→', 'leftarrow': '←', 'leftrightarrow': '↔',
            'Rightarrow': '⇒', 'implies': '⟹', 'Leftrightarrow': '⇔', 'iff': '⟺', 'mapsto': '↦',
            'partial': '∂', 'nabla': '∇', 'in': '∈', 'notin': '∉', 'ni': '∋',
            'subset': '⊂', 'subseteq': '⊆', 'supset': '⊃', 'supseteq': '⊇',
            'cup': '∪', 'cap': '∩', 'emptyset': '∅',
            'forall': '∀', 'exists': '∃', 'neg': '¬',
            'pm': '±', 'mp': '∓', 'oplus': '⊕', 'otimes': '⊗', 'odot': '⊙',
            'top': '⊤', 'bot': '⊥', 'perp': '⊥', 'parallel': '∥', 'mid': '∣',
            'langle': '⟨', 'rangle': '⟩', 'lfloor': '⌊', 'rfloor': '⌋', 'lceil': '⌈', 'rceil': '⌉',
            'quad': '&nbsp;&nbsp;', 'qquad': '&nbsp;&nbsp;&nbsp;&nbsp;'
        };

        for (const [k, v] of Object.entries(symbols)) {
            s = s.replace(new RegExp('\\\\' + k + '(?![a-zA-Z])', 'g'), v);
        }
        s = s.replace(/\\,/g, '&thinsp;').replace(/\\;/g, '&nbsp;');

        // 6. 单字符上下标 _x ^x 及残留上下标清理
        s = s.replace(/_\{([^{}]+)\}/g, '<sub>$1</sub>');
        s = s.replace(/\^\{([^{}]+)\}/g, '<sup>$1</sup>');
        s = s.replace(/_([a-zA-Z0-9\+\-])/g, '<sub>$1</sub>');
        s = s.replace(/\^([a-zA-Z0-9\+\-\*])/g, '<sup>$1</sup>');

        if (isBlock) {
            return `<div class="math-block">${s}</div>`;
        } else {
            return `<span class="math-inline">${s}</span>`;
        }
    }

    function renderMarkdownWithMath(md) {
        if (!md || !md.trim()) return '';
        // Choose a prefix absent from the source so user text cannot collide with slots.
        let prefix = '@@MD_SLOT_';
        while (md.includes(prefix)) prefix += '_';
        const slots = [];
        function stash(html) {
            const token = prefix + slots.length + '@@';
            slots.push({ token, html });
            return token;
        }
        // Code is opaque to every Markdown/math substitution, including newlines.
        let processed = md.replace(/```(?:[^\n`]*\n)?([\s\S]*?)```/g,
            (_, code) => stash('<pre><code>' + escapeHTML(code) + '</code></pre>'));
        processed = processed.replace(/`([^`\n]+)`/g,
            (_, code) => stash('<code>' + escapeHTML(code) + '</code>'));
        processed = processed.replace(/\\\$/g, () => stash('$'));
        processed = processed.replace(/\$\$([\s\S]+?)\$\$/g,
            (_, tex) => stash(renderLatexFormula(tex, true)));
        processed = processed.replace(/\\\[([\s\S]+?)\\\]/g,
            (_, tex) => stash(renderLatexFormula(tex, true)));
        processed = processed.replace(/\$([^$\n]+?)\$/g,
            (_, tex) => stash(renderLatexFormula(tex, false)));
        processed = processed.replace(/\\\(([\s\S]+?)\\\)/g,
            (_, tex) => stash(renderLatexFormula(tex, false)));

        // Support Markdown links [label](url), including jumpable PDF links dualpdf://jump?...
        processed = processed.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, rawUrl) => {
            const safeLabel = escapeHTML(label);
            const safeUrl = escapeHTML(rawUrl);
            const isJump = rawUrl.startsWith('dualpdf://jump');
            const cls = isJump ? 'pdf-jump-link' : 'md-ext-link';
            return stash(`<a href="${safeUrl}" class="${cls}" data-jump-url="${safeUrl}" onclick="return window.handleDualPDFJumpLink ? window.handleDualPDFJumpLink(this.getAttribute('data-jump-url'), event) : false;">${safeLabel}</a>`);
        });

        let html = escapeHTML(processed);
        html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
        html = html.replace(/\*([^*\n]+)\*/g, '<em>$1</em>');
        html = html.replace(/^### (.+)\n?/gm, '<h3>$1</h3>');
        html = html.replace(/^## (.+)\n?/gm, '<h2>$1</h2>');
        html = html.replace(/^# (.+)\n?/gm, '<h1>$1</h1>');
        html = html.replace(/^&gt; (.+)$/gm, '<blockquote class="md-quote">$1</blockquote>');
        html = html.replace(/^- (.+)$/gm, '• $1');
        html = html.replace(/\n/g, '<br>');
        for (const slot of slots) html = html.replace(slot.token, () => slot.html);
        return html;
    }

    function handleDualPDFJumpLink(url, evt) {
        if (evt) {
            evt.preventDefault();
            evt.stopPropagation();
        }
        if (!url) return false;
        const win = (typeof window !== 'undefined') ? window : null;
        const handlers = (win && win.webkit && win.webkit.messageHandlers) ? win.webkit.messageHandlers : null;
        if (!handlers) return false;
        if (handlers.columnNoteBridge) {
            handlers.columnNoteBridge.postMessage({ action: 'jumpLink', url: url });
        } else if (handlers.noteAction) {
            handlers.noteAction.postMessage({ action: 'jumpLink', id: '', extra: url });
        } else if (handlers.libraryBridge) {
            handlers.libraryBridge.postMessage({ action: 'noteJumpLink', url: url });
        }
        return false;
    }
    if (typeof window !== 'undefined') {
        window.handleDualPDFJumpLink = handleDualPDFJumpLink;
    }
