// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

/**
 * Single Responsibility: Registry and generator for the top 10 scientific LaTeX
 * publisher templates and top 10 academic citation styles.
 * Architecture: Pure Vala/GLib core data + template generator with zero UI dependencies.
 * Concurrency: Thread-safe static/immutable lookups.
 */

namespace Imladris.Core {

    public class LatexTemplateInfo : GLib.Object {
        public string id { get; construct; }
        public string name { get; construct; }
        public string publisher { get; construct; }
        public string document_class { get; construct; }
        public string class_options { get; construct; }
        public string layout_summary { get; construct; }
        public string description { get; construct; }
        public string default_citation_id { get; construct; }
        public string suggested_filename { get; construct; }
        public string extra_packages { get; construct; }
        public string frontmatter_macro { get; construct; }
        public string body_sections { get; construct; }

        public LatexTemplateInfo (
            string id,
            string name,
            string publisher,
            string document_class,
            string class_options,
            string layout_summary,
            string description,
            string default_citation_id,
            string suggested_filename,
            string extra_packages,
            string frontmatter_macro,
            string body_sections
        ) {
            Object (
                id: id,
                name: name,
                publisher: publisher,
                document_class: document_class,
                class_options: class_options,
                layout_summary: layout_summary,
                description: description,
                default_citation_id: default_citation_id,
                suggested_filename: suggested_filename,
                extra_packages: extra_packages,
                frontmatter_macro: frontmatter_macro,
                body_sections: body_sections
            );
        }
    }

    public class LatexCitationStyleInfo : GLib.Object {
        public string id { get; construct; }
        public string name { get; construct; }
        public string category { get; construct; }
        public string example_in_text { get; construct; }
        public string description { get; construct; }
        public string preamble_tex { get; construct; }
        public string cite_command { get; construct; }
        public string bibliography_tex { get; construct; }
        public bool uses_biblatex { get; construct; }

        public LatexCitationStyleInfo (
            string id,
            string name,
            string category,
            string example_in_text,
            string description,
            string preamble_tex,
            string cite_command,
            string bibliography_tex,
            bool uses_biblatex = false
        ) {
            Object (
                id: id,
                name: name,
                category: category,
                example_in_text: example_in_text,
                description: description,
                preamble_tex: preamble_tex,
                cite_command: cite_command,
                bibliography_tex: bibliography_tex,
                uses_biblatex: uses_biblatex
            );
        }
    }

    public class LatexTemplates : GLib.Object {

        /**
         * Returns the top 10 scientific publisher LaTeX templates.
         */
        public static GLib.GenericArray<LatexTemplateInfo> get_top_templates () {
            var list = new GLib.GenericArray<LatexTemplateInfo> ();

            // 1. IEEE Transactions / Conference
            list.add (new LatexTemplateInfo (
                "ieee",
                "IEEE Transactions & Conference",
                "IEEE",
                "IEEEtran",
                "journal",
                "Two-column · Letter",
                "Standard IEEEtran layout for IEEE journals, Transactions, and conference proceedings.",
                "ieee",
                "ieee_manuscript.tex",
                "\\usepackage{amsmath,amssymb,amsfonts}\n\\usepackage[version=4]{mhchem}\n\\usepackage{graphicx}\n\\usepackage{booktabs}\n\\usepackage{algorithm}\n\\usepackage{algorithmic}\n\\usepackage{textcomp}",
                "\\title{%TITLE%}\n\\author{%AUTHOR%\n  \\thanks{Department of Research, Institution Name. Email: author@institution.edu}}\n\\maketitle",
                "\\begin{abstract}\nConcise summary of the problem, methodology, key quantitative findings, and significance.\n\\end{abstract}\n\n\\begin{IEEEkeywords}\nScientific computing, reproducible research, statistical modeling.\n\\end{IEEEkeywords}\n\n\\section{Introduction}\n\\IEEEPARstart{S}{cientific} manuscripts in IEEE venues follow a structured two-column format. Prior work established the baseline methodology %CITE%.\n\n\\section{Methodology}\nWe formulate the objective function as:\n\\begin{equation}\n  \\mathcal{L}(\\theta) = \\frac{1}{N}\\sum_{i=1}^{N} \\ell(f_\\theta(x_i), y_i) + \\lambda \\|\\theta\\|_2^2\n\\end{equation}\n\n\\section{Experimental Results}\nTable~\\ref{tab:ieee_results} summarizes the benchmark comparison across cohorts.\n\\begin{table}[htbp]\n  \\caption{Benchmark Summary}\n  \\label{tab:ieee_results}\n  \\centering\n  \\begin{tabular}{lcc}\n    \\toprule\n    Model & Accuracy (\\%) & F1 Score \\\\\n    \\midrule\n    Baseline & 88.4 & 0.87 \\\\\n    Proposed & \\textbf{94.2} & \\textbf{0.93} \\\\\n    \\bottomrule\n  \\end{tabular}\n\\end{table}\n\n\\section{Conclusion}\nWe demonstrated consistent improvements over existing baselines and outlined future directions."
            ));

            // 2. ACM Proceedings / Journals
            list.add (new LatexTemplateInfo (
                "acm",
                "ACM Proceedings & Journals (acmart)",
                "ACM",
                "acmart",
                "sigconf",
                "Two-column · SIGCONF",
                "Official ACM Master Article Template (acmart) with CCS concepts and ACM Reference Format.",
                "acm",
                "acm_manuscript.tex",
                "\\usepackage{booktabs}\n\\usepackage{amsmath,amssymb}\n\\usepackage[version=4]{mhchem}\n\\usepackage{graphicx}",
                "\\title{%TITLE%}\n\\author{%AUTHOR%}\n\\affiliation{%\n  \\institution{Research Institute}\n  \\city{City}\n  \\country{Country}\n}\n\\email{author@institution.edu}",
                "\\begin{abstract}\nA clear and concise summary of the contribution, evaluation, and impact.\n\\end{abstract}\n\n\\begin{CCSXML}\n<ccs2012>\n  <concept>\n    <concept_id>10010147.10010257</concept_id>\n    <concept_desc>Computing methodologies~Machine learning</concept_desc>\n    <concept_significance>500</concept_significance>\n  </concept>\n</ccs2012>\n\\end{CCSXML}\n\\ccsdesc[500]{Computing methodologies~Machine learning}\n\\keywords{ACM, reproducible science, empirical evaluation}\n\n\\maketitle\n\n\\section{Introduction}\nModern computational research benefits from transparent, reproducible workflows %CITE%.\n\n\\section{System Design}\nDescribe architecture, formal guarantees, and implementation choices.\n\n\\section{Evaluation}\n\\begin{equation}\n  \\text{Speedup} = \\frac{T_{\\text{baseline}}}{T_{\\text{proposed}}}\n\\end{equation}\n\n\\section{Conclusion}\nSummarize the main findings and artifacts."
            ));

            // 3. Springer LNCS
            list.add (new LatexTemplateInfo (
                "springer_lncs",
                "Springer Lecture Notes in CS (LNCS)",
                "Springer",
                "llncs",
                "runningheads",
                "Single-column · LNCS",
                "Springer LNCS (llncs) format used across computer science conferences and workshops.",
                "splncs04",
                "lncs_manuscript.tex",
                "\\usepackage[T1]{fontenc}\n\\usepackage{graphicx}\n\\usepackage{amsmath,amssymb}\n\\usepackage[version=4]{mhchem}\n\\usepackage{booktabs}",
                "\\title{%TITLE%}\n\\author{%AUTHOR%\\orcidID{0000-0000-0000-0000}}\n\\authorrunning{%AUTHOR%}\n\\institute{Department of Computer Science, University Name \\\\\n\\email{author@university.edu}}\n\\maketitle",
                "\\begin{abstract}\nThe abstract should briefly summarize the contents of the paper in 150--250 words.\n\\keywords{First keyword \\and Second keyword \\and Third keyword.}\n\\end{abstract}\n\n\\section{Introduction}\nSpringer LNCS manuscripts use a clean single-column layout with numbered citations %CITE%.\n\n\\section{Preliminaries and Method}\n\\begin{equation}\n  E = mc^2\n\\end{equation}\n\n\\section{Experiments and Discussion}\nPresent empirical validation, ablation studies, and error analysis.\n\n\\section{Conclusion}\nConcluding remarks and future work."
            ));

            // 4. Elsevier Journal Article
            list.add (new LatexTemplateInfo (
                "elsevier",
                "Elsevier Journal Article (elsarticle)",
                "Elsevier",
                "elsarticle",
                "preprint,12pt",
                "Single-column · Preprint",
                "Official Elsevier elsarticle template with frontmatter, highlights, and Elsevier bibliography support.",
                "elsarticle-num",
                "elsevier_manuscript.tex",
                "\\usepackage{amsmath,amssymb}\n\\usepackage[version=4]{mhchem}\n\\usepackage{graphicx}\n\\usepackage{booktabs}\n\\usepackage{lineno}",
                "\\begin{frontmatter}\n\\title{%TITLE%}\n\\author[inst1]{%AUTHOR%}\n\\affiliation[inst1]{organization={Department of Sciences, University}, city={City}, country={Country}}\n\n\\begin{abstract}\nProvide a structured summary of background, methods, results, and conclusions.\n\\end{abstract}\n\n\\begin{keyword}\nElsevier \\sep Scientific article \\sep Empirical analysis\n\\end{keyword}\n\\end{frontmatter}",
                "\\linenumbers\n\n\\section{Introduction}\nState the objectives of the work and provide an adequate background, citing relevant literature %CITE%.\n\n\\section{Material and Methods}\nProvide sufficient detail to allow the work to be reproduced by an independent researcher.\n\n\\section{Results}\nResults should be clear and concise.\n\\begin{equation}\n  y_i = \\beta_0 + \\beta_1 x_i + \\varepsilon_i, \\quad \\varepsilon_i \\sim \\mathcal{N}(0, \\sigma^2)\n\\end{equation}\n\n\\section{Discussion}\nExplore the significance of the results of the work, not repeat them.\n\n\\section{Conclusions}\nThe main conclusions of the study may be presented in a short Conclusions section."
            ));

            // 5. Nature / Springer Nature Portfolio
            list.add (new LatexTemplateInfo (
                "nature",
                "Nature / Springer Nature Portfolio",
                "Nature Portfolio",
                "article",
                "11pt,a4paper",
                "Single-column · Nature Style",
                "Manuscript layout tailored for Nature, Nature Methods, and Springer Nature submissions.",
                "nature",
                "nature_manuscript.tex",
                "\\usepackage[margin=2.2cm]{geometry}\n\\usepackage{amsmath,amssymb,mhchem}\n\\usepackage{graphicx}\n\\usepackage{booktabs}\n\\usepackage{setspace}\n\\onehalfspacing",
                "\\title{\\textbf{%TITLE%}}\n\\author{%AUTHOR%$^{1,*}$ \\\\\n\\small $^{1}$Institute for Advanced Research \\\\\n\\small $^{*}$Correspondence: author@institute.org}\n\\date{}\n\\maketitle",
                "\\begin{abstract}\nA concise, referenced summary (150--200 words) stating the biological or physical problem, principal findings, and broader implications.\n\\end{abstract}\n\n\\section*{Introduction}\nIntroduce the scientific question and context for a broad multidisciplinary readership %CITE%.\n\n\\section*{Results}\nPresent key experimental and computational findings with statistical rigor.\n\\begin{equation}\n  \\Delta G = \\Delta H - T\\Delta S\n\\end{equation}\n\n\\section*{Discussion}\nInterpret the results in the context of prior work and highlight limitations.\n\n\\section*{Methods}\nDetail protocols, datasets, software versions, and statistical tests."
            ));

            // 6. PLOS ONE
            list.add (new LatexTemplateInfo (
                "plos",
                "PLOS ONE / PLOS Journals",
                "PLOS",
                "article",
                "10pt,letterpaper",
                "Single-column · Line-numbered",
                "Open-access PLOS submission format with line numbering, Author Summary, and Vancouver-style references.",
                "vancouver",
                "plos_manuscript.tex",
                "\\usepackage[top=0.85in,left=1.25in,footskip=0.75in]{geometry}\n\\usepackage{amsmath,amssymb}\n\\usepackage[version=4]{mhchem}\n\\usepackage{graphicx}\n\\usepackage{booktabs}\n\\usepackage{lineno}\n\\usepackage{setspace}\n\\doublespacing",
                "\\title{%TITLE%}\n\\author{%AUTHOR%$^{1*}$ \\\\\n\\small $^{1}$Department of Quantitative Biology, University \\\\\n\\small $^{*}$Corresponding author: author@university.edu}\n\\date{}\n\\maketitle\n\\linenumbers",
                "\\section*{Abstract}\nSummarize the background, methodology, principal findings, and conclusions (up to 300 words).\n\n\\section*{Author Summary}\nWrite a brief non-technical summary explaining why this research matters.\n\n\\section*{Introduction}\nProvide context and hypotheses tested in this study %CITE%.\n\n\\section*{Materials and Methods}\nDescribe study design, ethics approvals, data availability, and statistical analysis.\n\n\\section*{Results}\n\\begin{equation}\n  p = \\frac{1}{1 + e^{-(\\beta_0 + \\beta_1 x)}}\n\\end{equation}\n\n\\section*{Discussion}\nDiscuss implications, limitations, and future directions."
            ));

            // 7. APS / Physical Review (REVTeX 4.2)
            list.add (new LatexTemplateInfo (
                "aps",
                "APS Physical Review (REVTeX 4.2)",
                "American Physical Society",
                "revtex4-2",
                "aps,prl,twocolumn,superscriptaddress",
                "Two-column · PRL / PhysRev",
                "Official REVTeX 4.2 template for Physical Review Letters, Phys. Rev. A-E, and APS journals.",
                "aps",
                "aps_manuscript.tex",
                "\\usepackage{amsmath,amssymb}\n\\usepackage[version=4]{mhchem}\n\\usepackage{graphicx}\n\\usepackage{bm}\n\\usepackage{booktabs}",
                "\\title{%TITLE%}\n\\author{%AUTHOR%}\n\\email{author@physics.edu}\n\\affiliation{Department of Physics, Research University}\n\\date{\\today}",
                "\\begin{abstract}\nConcise summary of the physical phenomenon, theoretical or experimental approach, and main result.\n\\end{abstract}\n\n\\maketitle\n\n\\section{Introduction}\nRecent advances in quantum and statistical physics motivate this investigation %CITE%.\n\n\\section{Theory and Experiment}\nThe Hamiltonian of the coupled system is given by\n\\begin{equation}\n  \\hat{H} = \\sum_i \\hbar \\omega_i \\hat{a}_i^\\dagger \\hat{a}_i + \\sum_{i<j} g_{ij}(\\hat{a}_i^\\dagger \\hat{a}_j + \\text{h.c.})\n\\end{equation}\n\n\\section{Results and Discussion}\nAnalyze scaling behavior, uncertainties, and agreement with theory.\n\n\\begin{acknowledgments}\nWe thank the funding agencies and computing facilities that supported this work.\n\\end{acknowledgments}"
            ));

            // 8. NeurIPS
            list.add (new LatexTemplateInfo (
                "neurips",
                "NeurIPS Conference Paper",
                "NeurIPS",
                "article",
                "10pt",
                "Single-column · 5.5in textwidth",
                "NeurIPS-style machine learning conference manuscript with 5.5in text block, microtype, and booktabs.",
                "apa",
                "neurips_manuscript.tex",
                "\\usepackage[T1]{fontenc}\n\\usepackage[letterpaper,textwidth=5.5in,textheight=9in]{geometry}\n\\usepackage{amsmath,amssymb,amsfonts}\n\\usepackage[version=4]{mhchem}\n\\usepackage{microtype}\n\\usepackage{graphicx}\n\\usepackage{booktabs}\n\\usepackage{hyperref}",
                "\\title{%TITLE%}\n\\author{%AUTHOR% \\\\\n  Machine Learning Lab, University \\\\\n  \\texttt{author@university.edu}}\n\\date{}\n\\maketitle",
                "\\begin{abstract}\nSummarize the learning problem, theoretical or algorithmic contribution, and empirical results in one paragraph.\n\\end{abstract}\n\n\\section{Introduction}\nState the problem, motivation, and contributions clearly %CITE%.\n\n\\section{Method}\n\\begin{equation}\n  \\theta_{t+1} = \\theta_t - \\eta_t \\nabla_\\theta \\mathcal{L}(\\theta_t)\n\\end{equation}\n\n\\section{Experiments}\nReport mean and standard deviation across multiple random seeds.\n\n\\section{Conclusion and Broader Impact}\nSummarize findings, limitations, and societal considerations."
            ));

            // 9. ICML
            list.add (new LatexTemplateInfo (
                "icml",
                "ICML Conference Paper",
                "ICML",
                "article",
                "10pt,twocolumn",
                "Two-column · ML Proceedings",
                "Two-column International Conference on Machine Learning (ICML) manuscript layout with algorithm support.",
                "apa",
                "icml_manuscript.tex",
                "\\usepackage[T1]{fontenc}\n\\usepackage[letterpaper,margin=0.75in]{geometry}\n\\usepackage{amsmath,amssymb,amsthm}\n\\usepackage[version=4]{mhchem}\n\\usepackage{microtype}\n\\usepackage{graphicx}\n\\usepackage{booktabs}\n\\usepackage{algorithm}\n\\usepackage{algorithmic}\n\\usepackage{hyperref}",
                "\\title{\\textbf{%TITLE%}}\n\\author{%AUTHOR% \\\\\n  AI Research Group \\\\\n  \\texttt{author@research.org}}\n\\date{}\n\\maketitle",
                "\\begin{abstract}\nKeep abstracts to 4--6 sentences summarizing the core algorithmic advance and experimental validation.\n\\end{abstract}\n\n\\section{Introduction}\nIntroduce the learning setting and contrast with prior work %CITE%.\n\n\\section{Algorithm and Theoretical Analysis}\n\\begin{equation}\n  \\mathbb{E}[R(T)] \\le \\mathcal{O}(\\sqrt{T \\log K})\n\\end{equation}\n\n\\section{Empirical Evaluation}\nCompare against strong baselines on standard benchmarks.\n\n\\section{Conclusion}\nSummarize contributions and open questions."
            ));

            // 10. MDPI Open-Access Journal
            list.add (new LatexTemplateInfo (
                "mdpi",
                "MDPI Open-Access Journal",
                "MDPI",
                "article",
                "11pt,a4paper",
                "Single-column · A4 · Structured",
                "MDPI journal article template with structured sections, Author Contributions, and Conflicts of Interest.",
                "ieee",
                "mdpi_manuscript.tex",
                "\\usepackage[margin=2.0cm]{geometry}\n\\usepackage{amsmath,amssymb}\n\\usepackage[version=4]{mhchem}\n\\usepackage{graphicx}\n\\usepackage{booktabs}\n\\usepackage{hyperref}",
                "\\title{%TITLE%}\n\\author{%AUTHOR% $^{1,*}$ \\\\\n$^{1}$Department of Research, University; author@university.edu}\n\\date{}\n\\maketitle",
                "\\begin{abstract}\nA single paragraph of about 200 words maximum summarizing background, methods, results, and conclusions.\n\\end{abstract}\n\n\\noindent\\textbf{Keywords:} keyword 1; keyword 2; keyword 3\n\n\\section{Introduction}\nPlace the study in a broad context and highlight why it is important %CITE%.\n\n\\section{Materials and Methods}\nDescribe materials, protocols, and statistical analyses in sufficient detail for replication.\n\n\\section{Results and Discussion}\n\\begin{equation}\n  R^2 = 1 - \\frac{\\sum_i (y_i - \\hat{y}_i)^2}{\\sum_i (y_i - \\bar{y})^2}\n\\end{equation}\n\n\\section{Conclusions}\nSummarize the main takeaways.\n\n\\vspace{6pt}\n\\noindent\\textbf{Author Contributions:} Conceptualization, Methodology, Writing.\n\n\\noindent\\textbf{Conflicts of Interest:} The authors declare no conflicts of interest."
            ));

            return list;
        }

        /**
         * Returns the top 10 scientific citation & bibliography styles.
         */
        public static GLib.GenericArray<LatexCitationStyleInfo> get_top_citation_styles () {
            var list = new GLib.GenericArray<LatexCitationStyleInfo> ();

            // 1. IEEE Numeric
            list.add (new LatexCitationStyleInfo (
                "ieee",
                "IEEE (Numeric Brackets [1])",
                "Numeric · Engineering / CS",
                "[1], [2]–[4]",
                "Standard IEEE numeric citation order-of-appearance style (IEEEtran.bst).",
                "\\usepackage{cite}",
                "\\cite{example2026}",
                "\\bibliographystyle{IEEEtran}\n\\bibliography{%BIB%}"
            ));

            // 2. APA 7th (Author-Year)
            list.add (new LatexCitationStyleInfo (
                "apa",
                "APA 7th Edition (Author–Year)",
                "Author–Year · Psychology / ML / Social Sciences",
                "(Author & Collaborator, 2026)",
                "Author–year parenthetical & narrative citations via natbib (apalike).",
                "\\usepackage[round,authoryear]{natbib}",
                "\\citep{example2026}",
                "\\bibliographystyle{apalike}\n\\bibliography{%BIB%}"
            ));

            // 3. Nature (Superscript Numeric)
            list.add (new LatexCitationStyleInfo (
                "nature",
                "Nature (Superscript Numeric)",
                "Superscript · Life & Physical Sciences",
                "text^1,2–4",
                "Superscript compressed numeric citations used by Nature Portfolio journals.",
                "\\usepackage[super,comma,sort&compress]{natbib}",
                "\\cite{example2026}",
                "\\bibliographystyle{naturemag}\n\\bibliography{%BIB%}"
            ));

            // 4. Science (AAAS)
            list.add (new LatexCitationStyleInfo (
                "science",
                "Science / AAAS (Numeric)",
                "Numeric · Multidisciplinary Science",
                "(1, 2)",
                "AAAS Science journal numeric reference style with compressed ranges.",
                "\\usepackage[super,sort&compress]{natbib}",
                "\\cite{example2026}",
                "\\bibliographystyle{unsrtnat}\n\\bibliography{%BIB%}"
            ));

            // 5. ACM Reference Format
            list.add (new LatexCitationStyleInfo (
                "acm",
                "ACM Reference Format",
                "Numeric / Author–Year · Computing",
                "[1] or (Author et al., 2026)",
                "Official ACM-Reference-Format BibTeX style for ACM conferences and journals.",
                "\\usepackage{natbib}",
                "\\cite{example2026}",
                "\\bibliographystyle{ACM-Reference-Format}\n\\bibliography{%BIB%}"
            ));

            // 6. Springer LNCS (splncs04)
            list.add (new LatexCitationStyleInfo (
                "splncs04",
                "Springer LNCS (splncs04)",
                "Numeric · Springer CS",
                "[1]",
                "Springer Lecture Notes in Computer Science numeric reference style.",
                "\\usepackage{cite}",
                "\\cite{example2026}",
                "\\bibliographystyle{splncs04}\n\\bibliography{%BIB%}"
            ));

            // 7. Elsevier Numeric (elsarticle-num)
            list.add (new LatexCitationStyleInfo (
                "elsarticle-num",
                "Elsevier Numeric (elsarticle-num)",
                "Numeric · Elsevier Journals",
                "[1, 2]",
                "Elsevier standard numbered bibliography style with compressed ranges.",
                "\\usepackage[numbers,sort&compress]{natbib}",
                "\\cite{example2026}",
                "\\bibliographystyle{elsarticle-num}\n\\bibliography{%BIB%}"
            ));

            // 8. Vancouver / ICMJE (Biomedical)
            list.add (new LatexCitationStyleInfo (
                "vancouver",
                "Vancouver / ICMJE (Biomedical)",
                "Numeric · Medicine / PLOS / PubMed",
                "[1] or (1)",
                "ICMJE Vancouver numeric style used across biomedical and clinical journals.",
                "\\usepackage[numbers,sort&compress]{natbib}",
                "\\cite{example2026}",
                "\\bibliographystyle{vancouver}\n\\bibliography{%BIB%}"
            ));

            // 9. Chicago Author-Date (BibLaTeX)
            list.add (new LatexCitationStyleInfo (
                "chicago",
                "Chicago Author–Date (BibLaTeX)",
                "Author–Date · Humanities & Social Sciences",
                "(Author 2026, 12)",
                "Chicago Manual of Style author–date format using BibLaTeX + Biber.",
                "\\usepackage[style=authoryear,backend=biber]{biblatex}\n\\addbibresource{%BIB%.bib}",
                "\\parencite{example2026}",
                "\\printbibliography",
                true
            ));

            // 10. APS / MDPI / MLA-style BibLaTeX or numeric
            list.add (new LatexCitationStyleInfo (
                "aps",
                "APS / Physical Review (apsrev4-2)",
                "Numeric · Physics",
                "[1]",
                "American Physical Society apsrev4-2 style with DOI and eprint links.",
                "\\usepackage[numbers,sort&compress]{natbib}",
                "\\cite{example2026}",
                "\\bibliographystyle{apsrev4-2}\n\\bibliography{%BIB%}"
            ));

            return list;
        }

        public static LatexTemplateInfo? find_template (string id) {
            var all = get_top_templates ();
            for (int i = 0; i < all.length; i++) {
                if (all[i].id == id) return all[i];
            }
            return null;
        }

        public static LatexCitationStyleInfo? find_citation_style (string id) {
            var all = get_top_citation_styles ();
            for (int i = 0; i < all.length; i++) {
                if (all[i].id == id) return all[i];
            }
            return null;
        }

        public static string escape_latex_text (string text) {
            return text
                .replace ("\\", "\\textbackslash{}")
                .replace ("&", "\\&")
                .replace ("%", "\\%")
                .replace ("$", "\\$")
                .replace ("#", "\\#")
                .replace ("_", "\\_")
                .replace ("{", "\\{")
                .replace ("}", "\\}");
        }

        /**
         * Generates a complete, ready-to-compile LaTeX manuscript combining the
         * chosen publisher template and citation style.
         */
        public static string generate_document (
            LatexTemplateInfo tpl,
            LatexCitationStyleInfo cite_style,
            string title,
            string author,
            string bib_basename = "references"
        ) {
            string safe_title = escape_latex_text (title.strip () != "" ? title.strip () : "Untitled Scientific Manuscript");
            string safe_author = escape_latex_text (author.strip () != "" ? author.strip () : GLib.Environment.get_real_name ());
            string safe_bib = bib_basename.strip ();
            if (safe_bib.has_suffix (".bib")) {
                safe_bib = safe_bib.substring (0, safe_bib.length - 4).strip ();
            }
            if (safe_bib == "") {
                safe_bib = "references";
            }

            string doc_class_line = tpl.class_options.length > 0
                ? @"\\documentclass[$(tpl.class_options)]{$(tpl.document_class)}"
                : @"\\documentclass{$(tpl.document_class)}";

            bool class_loads_natbib = (tpl.document_class == "acmart" || tpl.document_class == "revtex4-2" || tpl.document_class == "elsarticle");
            string cite_preamble = cite_style.preamble_tex.replace ("%BIB%", safe_bib);
            string bib_block = cite_style.bibliography_tex.replace ("%BIB%", safe_bib);
            string cite_cmd = cite_style.cite_command;

            if (class_loads_natbib) {
                if (cite_style.uses_biblatex) {
                    // Document class auto-loads natbib, which conflicts with biblatex; use natbib author-year fallback
                    cite_preamble = "% Author-year citation support provided by document class (" + tpl.document_class + " natbib)";
                    bib_block = @"\\bibliographystyle{apalike}\n\\bibliography{$safe_bib}";
                    cite_cmd = "\\citep{example2026}";
                } else if (cite_preamble.contains ("natbib")) {
                    cite_preamble = "% Citation support provided by document class (" + tpl.document_class + ")";
                }
            }

            string front = tpl.frontmatter_macro
                .replace ("%TITLE%", safe_title)
                .replace ("%AUTHOR%", safe_author);

            string body = tpl.body_sections
                .replace ("%CITE%", cite_cmd);

            var sb = new GLib.StringBuilder ();
            sb.append ("%% Template: ").append (tpl.name).append (" (").append (tpl.publisher).append (")\n");
            sb.append ("%% Citation Style: ").append (cite_style.name).append ("\n");
            sb.append (doc_class_line).append ("\n\n");
            // Load citation packages before extra_packages so hyperref (when present) stays last
            if (cite_preamble.length > 0) {
                sb.append (cite_preamble).append ("\n");
            }
            sb.append (tpl.extra_packages).append ("\n");
            sb.append ("\n\\begin{document}\n\n");
            sb.append (front).append ("\n\n");
            sb.append (body).append ("\n\n");
            sb.append (bib_block).append ("\n\n");
            sb.append ("\\end{document}\n");

            return sb.str;
        }
    }
}
