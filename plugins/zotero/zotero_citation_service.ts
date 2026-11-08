/**
 * ZoteroService.ts
 * 
 * Sandbox-friendly Zotero integration service for Imladris Scientific Editor.
 * Communicates via localhost HTTP (127.0.0.1:23119) and falls back to local .bib files
 * to remain 100% compliant with Flathub sandboxing policies.
 */

export interface CitationItem {
  citekey: string;
  title: string;
  authors: string;
  year: string;
  abstract?: string;
  source: 'better-bibtex' | 'zotero-local' | 'local-bib';
}

interface BBTJsonRpcResponse<T> {
  jsonrpc: string;
  result?: T;
  error?: {
    code: number;
    message: string;
  };
  id: number | null;
}

export class ZoteroService {
  private readonly baseUrl = 'http://127.0.0.1:23119';
  private readonly timeoutMs = 1500;

  /**
   * Checks if the Zotero desktop client is running on the host or in a Flatpak.
   */
  public async isZoteroRunning(): Promise<boolean> {
    try {
      const response = await this.fetchWithTimeout(`${this.baseUrl}/connector/ping`, {
        method: 'GET',
      });
      if (!response.ok) return false;
      const text = await response.text();
      return text.includes('Zotero is running');
    } catch {
      return false;
    }
  }

  /**
   * Checks if the Better BibTeX (BBT) plugin is active inside Zotero.
   */
  public async isBetterBibTeXAvailable(): Promise<boolean> {
    try {
      const response = await this.fetchWithTimeout(`${this.baseUrl}/better-bibtex/json-rpc`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          jsonrpc: '2.0',
          method: 'item.search',
          params: [''],
          id: 1,
        }),
      });
      return response.ok;
    } catch {
      return false;
    }
  }

  /**
   * Searches for citations across Better BibTeX, Native Zotero Local API, or a fallback .bib string.
   */
  public async searchCitations(query: string, fallbackBibContent?: string): Promise<CitationItem[]> {
    const trimmedQuery = query.trim();

    // Tier 1A: Try Better BibTeX JSON-RPC first (Best for Quarto / R Markdown)
    try {
      const bbtResults = await this.searchBetterBibTeX(trimmedQuery);
      if (bbtResults.length > 0) {
        return bbtResults;
      }
    } catch {
      // Fall through to Native Zotero Local API
    }

    // Tier 1B: Try Zotero 7+ Native Local API
    try {
      const nativeResults = await this.searchNativeZotero(trimmedQuery);
      if (nativeResults.length > 0) {
        return nativeResults;
      }
    } catch {
      // Fall through to Offline .bib file parser
    }

    // Tier 2: Offline Fallback using project's references.bib content
    if (fallbackBibContent) {
      return this.searchOfflineBib(trimmedQuery, fallbackBibContent);
    }

    return [];
  }

  /**
   * Searches Zotero via Better BibTeX JSON-RPC endpoint.
   */
  private async searchBetterBibTeX(query: string): Promise<CitationItem[]> {
    const response = await this.fetchWithTimeout(`${this.baseUrl}/better-bibtex/json-rpc`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'item.search',
        params: [query],
        id: Date.now(),
      }),
    });

    if (!response.ok) {
      throw new Error(`BBT HTTP error: ${response.status}`);
    }

    const data = (await response.json()) as BBTJsonRpcResponse<any[]>;
    if (data.error || !Array.isArray(data.result)) {
      throw new Error(data.error?.message || 'Invalid BBT response');
    }

    return data.result.map((item) => {
      const authors = Array.isArray(item.author)
        ? item.author.map((a: any) => a.family || a.literal || '').filter(Boolean).join(', ')
        : 'Unknown Author';

      const year = item.issued?.['date-parts']?.[0]?.[0]?.toString() || 'n.d.';

      return {
        citekey: item.citekey || item['citation-key'],
        title: item.title || 'Untitled',
        authors,
        year,
        abstract: item.abstract,
        source: 'better-bibtex',
      };
    });
  }

  /**
   * Searches Zotero's built-in local HTTP API (when Better BibTeX is not installed).
   */
  private async searchNativeZotero(query: string): Promise<CitationItem[]> {
    const encodedQuery = encodeURIComponent(query);
    const url = `${this.baseUrl}/api/users/0/items?format=json&q=${encodedQuery}&itemType=-attachment`;

    const response = await this.fetchWithTimeout(url, { method: 'GET' });
    if (!response.ok) {
      throw new Error(`Native Zotero API error: ${response.status}`);
    }

    const items = (await response.json()) as any[];
    return items
      .filter((item) => item.data && item.data.title)
      .map((item) => {
        const creators = Array.isArray(item.data.creators) ? item.data.creators : [];
        const firstAuthor = creators[0]?.lastName || creators[0]?.name || 'anon';
        const authors = creators
          .map((c: any) => c.lastName || c.name || '')
          .filter(Boolean)
          .join(', ');

        const yearMatch = (item.data.date || '').match(/\b(19|20)\d{2}\b/);
        const year = yearMatch ? yearMatch[0] : 'nd';

        // Construct a deterministic fallback citation key if BBT is not present
        const sanitizedAuthor = firstAuthor.toLowerCase().replace(/[^a-z0-9]/g, '');
        const citekey = `${sanitizedAuthor}${year}`;

        return {
          citekey,
          title: item.data.title,
          authors: authors || 'Unknown Author',
          year,
          abstract: item.data.abstractNote,
          source: 'zotero-local',
        };
      });
  }

  /**
   * Opens Zotero's native "Cite As You Write" (CAYW) quick-search bar on the desktop
   * and returns the formatted Pandoc citation string (e.g., "[@turing1950; @shannon1948]").
   */
  public async openNativeCitationPicker(): Promise<string | null> {
    try {
      const url = `${this.baseUrl}/better-bibtex/cayw?format=pandoc&brackets=1`;
      // Native picker needs a longer timeout while the user selects papers
      const response = await this.fetchWithTimeout(url, { method: 'GET' }, 60000);
      if (!response.ok) return null;
      const citationString = await response.text();
      return citationString.trim() || null;
    } catch {
      return null;
    }
  }

  /**
   * Exports raw BibTeX entries for an array of citation keys so Imladris can automatically
   * append them to the Quarto/R Markdown project's `references.bib` file.
   */
  public async exportBibTeXEntries(citekeys: string[]): Promise<string> {
    if (citekeys.length === 0) return '';

    const response = await this.fetchWithTimeout(`${this.baseUrl}/better-bibtex/json-rpc`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        jsonrpc: '2.0',
        method: 'item.export',
        params: [citekeys, 'Better BibTeX'],
        id: Date.now(),
      }),
    });

    if (!response.ok) {
      throw new Error(`Failed to export BibTeX from Zotero: ${response.status}`);
    }

    const data = (await response.json()) as BBTJsonRpcResponse<string>;
    if (data.error || typeof data.result !== 'string') {
      throw new Error(data.error?.message || 'Empty BibTeX export');
    }

    return data.result;
  }

  /**
   * Merges newly exported BibTeX entries into an existing `references.bib` content string
   * without duplicating existing citation keys.
   */
  public mergeIntoBibFileContent(existingBibContent: string, newBibEntry: string, citekey: string): string {
    const keyRegex = new RegExp(`@[a-zA-Z]+\\s*\\{\\s*${this.escapeRegExp(citekey)}\\s*,`, 'i');
    if (keyRegex.test(existingBibContent)) {
      // Entry already exists in references.bib
      return existingBibContent;
    }

    const separator = existingBibContent.endsWith('\n\n')
      ? ''
      : existingBibContent.endsWith('\n')
      ? '\n'
      : '\n\n';

    return `${existingBibContent}${separator}${newBibEntry.trim()}\n`;
  }

  /**
   * Ensures the YAML frontmatter of a Quarto (.qmd) or R Markdown (.Rmd) document
   * references the target `.bib` file.
   */
  public ensureYamlBibliography(documentText: string, bibFilename = 'references.bib'): string {
    const yamlRegex = /^---\r?\n([\s\S]*?)\r?\n---/;
    const match = documentText.match(yamlRegex);

    if (!match) {
      // Create new YAML frontmatter block at the top of the document
      return `---\nbibliography: ${bibFilename}\n---\n\n${documentText}`;
    }

    const yamlContent = match[1];
    if (/^bibliography\s*:/m.test(yamlContent)) {
      return documentText;
    }

    const updatedYaml = `---\n${yamlContent}\nbibliography: ${bibFilename}\n---`;
    return documentText.replace(yamlRegex, updatedYaml);
  }

  /**
   * Lightweight offline `.bib` parser fallback when Zotero is closed.
   */
  public searchOfflineBib(query: string, bibContent: string): CitationItem[] {
    const entries: CitationItem[] = [];
    const entryRegex = /@([a-zA-Z]+)\s*\{\s*([^,\s]+)\s*,([\s\S]*?)(?=\n@[a-zA-Z]+\s*\{|\s*$)/g;
    const lowerQuery = query.toLowerCase();

    let match: RegExpExecArray | null;
    while ((match = entryRegex.exec(bibContent)) !== null) {
      const citekey = match[2].trim();
      const body = match[3];

      const title = this.extractBibField(body, 'title') || 'Untitled';
      const authors = this.extractBibField(body, 'author') || 'Unknown Author';
      const year = this.extractBibField(body, 'year') || 'eb';

      const searchableText = `${citekey} ${title} ${authors} ${year}`.toLowerCase();
      if (!lowerQuery || searchableText.includes(lowerQuery)) {
        entries.push({
          citekey,
          title: title.replace(/[{}]/g, ''),
          authors: authors.replace(/[{}]/g, ''),
          year,
          source: 'local-bib',
        });
      }
    }

    return entries;
  }

  /**
   * Returns the XDG Portal-compatible URI to highlight an item directly inside the Zotero app.
   */
  public getZoteroSelectUri(citekey: string): string {
    return `zotero://select/items/@${encodeURIComponent(citekey)}`;
  }

  private extractBibField(entryBody: string, fieldName: string): string | null {
    const regex = new RegExp(`${fieldName}\\s*=\\s*(?:\\{([\\s\\S]*?)\\}|"([\\s\\S]*?)"|(\\d+))`, 'i');
    const match = entryBody.match(regex);
    if (!match) return null;
    return (match[1] || match[2] || match[3] || '').trim();
  }

  private escapeRegExp(str: string): string {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  private async fetchWithTimeout(
    url: string,
    options: RequestInit,
    customTimeoutMs?: number
  ): Promise<Response> {
    const controller = new AbortController();
    const id = setTimeout(() => controller.abort(), customTimeoutMs ?? this.timeoutMs);
    try {
      return await fetch(url, {
        ...options,
        signal: controller.signal,
      });
    } finally {
      clearTimeout(id);
    }
  }
}