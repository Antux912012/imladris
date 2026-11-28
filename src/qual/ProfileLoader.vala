// SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
// SPDX-License-Identifier: Apache-2.0

using GLib;

namespace Imladris.Qual {

    /**
     * Domain Profile Loader and Seeder for YAML-defined qualitative codebooks.
     * Supports proteomics, gene expression, clinical narratives, and financial filings.
     */
    public class ProfileLoader : GLib.Object {

        public static QualDomainProfile parse_yaml (string yaml_text) {
            var profile = new QualDomainProfile ();
            string[] raw_lines = yaml_text.split ("\n");

            string section = "";
            string current_scale = "";

            var code_stack = new Gee.ArrayList<QualCodeDef> ();
            var indent_stack = new Gee.ArrayList<int> ();

            for (int idx = 0; idx < raw_lines.length; idx++) {
                string raw = strip_yaml_comment (raw_lines[idx]);
                if (raw.strip () == "" || raw.strip () == "---") continue;

                int indent = count_indent (raw);
                string trimmed = raw.strip ();

                if (indent == 0 && !trimmed.has_prefix ("-")) {
                    code_stack.clear ();
                    indent_stack.clear ();
                    current_scale = "";
                    int colon = trimmed.index_of_char (':');
                    if (colon > 0) {
                        string k = trimmed.substring (0, colon).strip ();
                        string v = unquote_yaml (trimmed.substring (colon + 1).strip ());
                        switch (k) {
                            case "profile_id":
                                profile.profile_id = v;
                                if (v.has_prefix ("protein")) profile.domain_slug = "protein";
                                else if (v.has_prefix ("gene")) profile.domain_slug = "gene-expr";
                                else if (v.has_prefix ("finance")) profile.domain_slug = "finance";
                                else if (v.has_prefix ("clinical")) profile.domain_slug = "clinical";
                                break;
                            case "domain":
                                profile.domain_slug = v;
                                break;
                            case "name":
                                profile.name = v;
                                break;
                            case "version":
                                profile.version = v;
                                break;
                            case "entity_resolver":
                                profile.entity_resolver = v;
                                break;
                            case "scales":
                                section = "scales";
                                break;
                            case "codes":
                                section = "codes";
                                break;
                            default:
                                section = "";
                                break;
                        }
                    }
                    continue;
                }

                if (section == "scales") {
                    if (trimmed.has_prefix ("- ")) {
                        if (current_scale != "") {
                            var list = profile.scales.get (current_scale);
                            if (list != null) {
                                list.add (unquote_yaml (trimmed.substring (2).strip ()));
                            }
                        }
                    } else {
                        int colon = trimmed.index_of_char (':');
                        if (colon > 0) {
                            current_scale = trimmed.substring (0, colon).strip ();
                            string rhs = trimmed.substring (colon + 1).strip ();
                            var list = new Gee.ArrayList<string> ();
                            if (rhs.has_prefix ("[") && rhs.has_suffix ("]")) {
                                string inner = rhs.substring (1, rhs.length - 2);
                                foreach (string item in inner.split (",")) {
                                    string clean = unquote_yaml (item.strip ());
                                    if (clean != "") list.add (clean);
                                }
                            }
                            profile.scales.set (current_scale, list);
                        }
                    }
                    continue;
                }

                if (section == "codes") {
                    if (trimmed.has_prefix ("- ") || trimmed == "-") {
                        while (indent_stack.size > 0 && indent <= indent_stack.get (indent_stack.size - 1)) {
                            indent_stack.remove_at (indent_stack.size - 1);
                            code_stack.remove_at (code_stack.size - 1);
                        }
                        var node = new QualCodeDef ("", "");
                        if (code_stack.size == 0) {
                            profile.codes.add (node);
                        } else {
                            var parent = code_stack.get (code_stack.size - 1);
                            node.parent_id = parent.id;
                            node.color = parent.color;
                            parent.children.add (node);
                        }
                        code_stack.add (node);
                        indent_stack.add (indent);

                        if (trimmed.length > 2) {
                            apply_code_field (node, trimmed.substring (2).strip ());
                        }
                    } else if (code_stack.size > 0) {
                        var active = code_stack.get (code_stack.size - 1);
                        apply_code_field (active, trimmed);
                        foreach (var ch in active.children) {
                            if (ch.parent_id == null || ch.parent_id == "") {
                                ch.parent_id = active.id;
                            }
                        }
                    }
                }
            }

            if (profile.domain_slug == "general" && profile.profile_id != "") {
                int dash = profile.profile_id.index_of_char ('-');
                if (dash > 0) profile.domain_slug = profile.profile_id.substring (0, dash);
            }
            profile.flatten_codes ();
            return profile;
        }

        private static void apply_code_field (QualCodeDef node, string field_line) {
            int colon = field_line.index_of_char (':');
            if (colon <= 0) return;
            string k = field_line.substring (0, colon).strip ();
            string v = unquote_yaml (field_line.substring (colon + 1).strip ());
            switch (k) {
                case "id":
                    node.id = v;
                    break;
                case "label":
                    node.label = v;
                    break;
                case "color":
                    if (v != "") node.color = v;
                    break;
                default:
                    break;
            }
        }

        private static int count_indent (string line) {
            int n = 0;
            while (n < line.length) {
                if (line[n] == ' ') n++;
                else if (line[n] == '\t') n += 2;
                else break;
            }
            return n;
        }

        private static string strip_yaml_comment (string line) {
            bool in_q = false;
            char qc = '"';
            for (int i = 0; i < line.length; i++) {
                char c = line[i];
                if (in_q) {
                    if (c == '\\' && i + 1 < line.length) { i++; continue; }
                    if (c == qc) in_q = false;
                } else {
                    if (c == '"' || c == '\'') {
                        in_q = true;
                        qc = c;
                    } else if (c == '#' && (i == 0 || line[i - 1].isspace ())) {
                        return line.substring (0, i);
                    }
                }
            }
            return line;
        }

        private static string unquote_yaml (string val) {
            string s = val.strip ();
            if (s.length >= 2 && ((s.has_prefix ("\"") && s.has_suffix ("\"")) ||
                                  (s.has_prefix ("'") && s.has_suffix ("'")))) {
                return s.substring (1, s.length - 2);
            }
            return s;
        }

        public static QualDomainProfile? load_from_file (string file_path) {
            try {
                string contents;
                GLib.FileUtils.get_contents (file_path, out contents);
                return parse_yaml (contents);
            } catch (GLib.Error e) {
                GLib.warning ("Failed to load domain profile %s: %s", file_path, e.message);
                return null;
            }
        }

        public static Gee.ArrayList<QualDomainProfile> load_all_profiles (string? workspace_dir = null) {
            string user_dir = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "imladris", "profiles");
            ensure_default_profiles_in_dir (user_dir);

            var by_id = new Gee.HashMap<string, QualDomainProfile> ();
            var ordered = new Gee.ArrayList<QualDomainProfile> ();

            string[] dirs = (workspace_dir != null && workspace_dir != "")
                ? new string[] { GLib.Path.build_filename (workspace_dir, ".imladris", "profiles"), user_dir }
                : new string[] { user_dir };

            foreach (string d in dirs) {
                if (!GLib.FileUtils.test (d, GLib.FileTest.IS_DIR)) continue;
                try {
                    var dir = GLib.Dir.open (d, 0);
                    string? fname = null;
                    while ((fname = dir.read_name ()) != null) {
                        if (!fname.has_suffix (".yaml") && !fname.has_suffix (".yml")) continue;
                        var p = load_from_file (GLib.Path.build_filename (d, fname));
                        if (p != null && p.profile_id != "" && !by_id.has_key (p.profile_id)) {
                            by_id.set (p.profile_id, p);
                            ordered.add (p);
                        }
                    }
                } catch (GLib.Error e) {}
            }
            ordered.sort ((a, b) => strcmp (a.name, b.name));
            return ordered;
        }

        public static void ensure_default_profiles_in_dir (string dir_path) {
            GLib.DirUtils.create_with_parents (dir_path, 0755);
            write_if_missing (GLib.Path.build_filename (dir_path, "protein-qual.yaml"), default_protein_yaml ());
            write_if_missing (GLib.Path.build_filename (dir_path, "gene-expr-qual.yaml"), default_gene_expr_yaml ());
            write_if_missing (GLib.Path.build_filename (dir_path, "finance-qual.yaml"), default_finance_yaml ());
            write_if_missing (GLib.Path.build_filename (dir_path, "clinical-qual.yaml"), default_clinical_yaml ());
        }

        private static void write_if_missing (string path, string content) {
            if (!GLib.FileUtils.test (path, GLib.FileTest.EXISTS)) {
                try {
                    GLib.FileUtils.set_contents (path, content);
                } catch (GLib.Error e) {}
            }
        }

        public static string default_protein_yaml () {
            return """profile_id: "protein-qual-v1"
domain: "protein"
name: "Protein Qualitative Analysis"
version: "1.0.0"
entity_resolver: "yavanna:uniprot"
scales:
  confidence: ["low", "moderate", "high"]
  valence: ["positive", "neutral", "negative", "ambiguous"]
codes:
  - id: "localization"
    label: "Subcellular Localization"
    color: "#88C0D0"
    children:
      - id: "loc-nuclear"
        label: "Nuclear"
        color: "#88C0D0"
      - id: "loc-cytosolic"
        label: "Cytosolic"
        color: "#81A1C1"
      - id: "loc-membrane"
        label: "Plasma Membrane"
        color: "#5E81AC"
  - id: "ptm-dysregulation"
    label: "PTM Dysregulation"
    color: "#BF616A"
    children:
      - id: "ptm-hyperphos"
        label: "Hyperphosphorylation"
        color: "#BF616A"
      - id: "ptm-ubiquitin"
        label: "Ubiquitin-Proteasome"
        color: "#D08770"
  - id: "ppi-complex"
    label: "Protein Interaction Complex"
    color: "#A3BE8C"
""";
        }

        public static string default_gene_expr_yaml () {
            return """profile_id: "gene-expr-qual-v1"
domain: "gene-expr"
name: "Gene Expression & Transcriptomics"
version: "1.0.0"
entity_resolver: "yavanna:ensembl"
scales:
  confidence: ["low", "moderate", "high"]
  valence: ["upregulated", "neutral", "downregulated", "biphasic"]
codes:
  - id: "diff-expression"
    label: "Differential Expression"
    color: "#88C0D0"
    children:
      - id: "deg-up"
        label: "Transcriptional Upregulation"
        color: "#A3BE8C"
      - id: "deg-down"
        label: "Transcriptional Repression"
        color: "#BF616A"
  - id: "pathway-enrichment"
    label: "Pathway & GO Enrichment"
    color: "#B48EAD"
    children:
      - id: "go-immune"
        label: "Innate Immune Signaling"
        color: "#B48EAD"
      - id: "go-apoptosis"
        label: "Apoptotic Cascade"
        color: "#EBCB8B"
  - id: "splicing-isoform"
    label: "Alternative Splicing Isoform"
    color: "#81A1C1"
""";
        }

        public static string default_finance_yaml () {
            return """profile_id: "finance-qual-v1"
domain: "finance"
name: "Financial Filings & Risk Analysis"
version: "1.0.0"
entity_resolver: "yavanna:sec-ticker"
scales:
  confidence: ["low", "moderate", "high"]
  valence: ["positive", "neutral", "negative", "hedged"]
codes:
  - id: "risk-factors"
    label: "Material Risk Factors"
    color: "#BF616A"
    children:
      - id: "risk-liquidity"
        label: "Liquidity & Covenant Exposure"
        color: "#BF616A"
      - id: "risk-supply-chain"
        label: "Supply Chain Concentration"
        color: "#D08770"
  - id: "guidance-outlook"
    label: "Forward Guidance & Margin"
    color: "#A3BE8C"
    children:
      - id: "guide-expansion"
        label: "Margin Expansion"
        color: "#A3BE8C"
      - id: "guide-headwind"
        label: "Macroeconomic Headwind"
        color: "#EBCB8B"
  - id: "regulatory-disclosure"
    label: "SEC / Regulatory Disclosure"
    color: "#88C0D0"
""";
        }

        public static string default_clinical_yaml () {
            return """profile_id: "clinical-qual-v1"
domain: "clinical"
name: "Clinical Narratives & Safety (GCP)"
version: "1.0.0"
entity_resolver: "yavanna:clinical"
scales:
  confidence: ["low", "moderate", "high"]
  valence: ["favorable", "neutral", "adverse", "serious-ae"]
codes:
  - id: "adverse-event"
    label: "Adverse Event Narrative"
    color: "#BF616A"
    children:
      - id: "ae-grade3plus"
        label: "CTCAE Grade >= 3"
        color: "#BF616A"
      - id: "ae-resolved"
        label: "Resolved Without Sequelae"
        color: "#A3BE8C"
  - id: "protocol-deviation"
    label: "Protocol Deviation (GCP)"
    color: "#EBCB8B"
  - id: "clinical-response"
    label: "Biomarker / Clinical Response"
    color: "#88C0D0"
""";
        }
    }
}
