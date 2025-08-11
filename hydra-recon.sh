cat > hydra-recon.sh <<'EOF'
#!/usr/bin/env bash
# Hydra Recon - simple orchestrator (bash)
# Use only on targets you are authorized to test.

set -o errexit
set -o nounset
set -o pipefail

TARGET="\${1:-}"
OUTDIR="\${2:-hydra_output}"
WORDLIST="\${3:-wordlists/subdomains.txt}"
THREADS="\${THREADS:-50}"
SQLMAP_OPTS="--batch --threads=3"

if [[ -z "\$TARGET" ]]; then
  echo "Usage: \$0 <target-domain> [output-dir] [optional-wordlist]"
  echo "Example: \$0 example.com hydra_out wordlists/subdomains.txt"
  exit 1
fi

mkdir -p "\$OUTDIR"
echo "[*] Hydra Recon started for: \$TARGET"
echo "[*] Output dir: \$OUTDIR"

GREEN=\"\\e[32m\"; YELLOW=\"\\e[33m\"; RESET=\"\\e[0m\"

SUBS_RAW=\"\$OUTDIR/subs_raw.txt\"
> \"\$SUBS_RAW\"

echo -e \"\${YELLOW}[*] Phase 1: Subdomain enumeration (subfinder, assetfinder, crt.sh, amass)...\${RESET}\"

# subfinder
if command -v subfinder >/dev/null 2>&1; then
  subfinder -d \"\$TARGET\" -silent -o \"\$OUTDIR/subfinder.txt\" || true
fi

# assetfinder
if command -v assetfinder >/dev/null 2>&1; then
  assetfinder --subs-only \"\$TARGET\" > \"\$OUTDIR/assetfinder.txt\" || true
fi

# crt.sh
curl -s \"https://crt.sh/?q=%25.\$TARGET&output=json\" | jq -r '.[].name_value' 2>/dev/null | sed 's/\\*\\.//g' > \"\$OUTDIR/crtsh.txt\" || true

# amass (optional)
if command -v amass >/dev/null 2>&1; then
  amass enum -passive -d \"\$TARGET\" -o \"\$OUTDIR/amass.txt\" || true
fi

# combine lists, normalize and dedupe
cat \"\$OUTDIR\"/subfinder.txt \"\$OUTDIR\"/assetfinder.txt \"\$OUTDIR\"/crtsh.txt \"\$OUTDIR\"/amass.txt 2>/dev/null | tr '[:upper:]' '[:lower:]' | sed 's/\\r//g' | sort -u > \"\$SUBS_RAW\" || true

# add wordlist-derived subdomains if file exists
if [[ -f \"\$WORDLIST\" ]]; then
  while IFS= read -r w; do
    [[ -z \"\$w\" ]] && continue
    echo \"\${w}.\$TARGET\"
  done < \"\$WORDLIST\" >> \"\$SUBS_RAW\" || true
fi

sort -u \"\$SUBS_RAW\" -o \"\$SUBS_RAW\" || true
echo -e \"\${GREEN}[+] Subdomain list: \$(wc -l < \"\$SUBS_RAW\") entries -> \$SUBS_RAW\${RESET}\"

####################
# Phase 2: Probe HTTP(S) (httpx)
####################
echo -e \"\${YELLOW}[*] Phase 2: Resolve & HTTP probe (httpx)...\${RESET}\"
LIVE=\"\$OUTDIR/live_hosts.txt\"
if command -v httpx >/dev/null 2>&1; then
  httpx -l \"\$SUBS_RAW\" -silent -threads \"\$THREADS\" -ports 80,443,8080,8443 -status-code -title -o \"\$OUTDIR/httpx.txt\" || true
  awk '{print \$1}' \"\$OUTDIR/httpx.txt\" | sed -E 's|https?://||' | sed -E 's|:.*$||' | sort -u > \"\$LIVE\" || true
else
  echo \"[!] httpx not found; skipping HTTP probe.\"
  # fallback: use subs list as live list (not accurate)
  cp \"\$SUBS_RAW\" \"\$LIVE\" || true
fi
echo -e \"\${GREEN}[+] Live hosts saved to \$LIVE\${RESET}\"

####################
# Phase 3: Nuclei + takeover checks
####################
echo -e \"\${YELLOW}[*] Phase 3: Nuclei & takeover checks (nuclei, subjack)...\${RESET}\"
if command -v nuclei >/dev/null 2>&1; then
  nuclei -l \"\$LIVE\" -silent -o \"\$OUTDIR/nuclei_all.txt\" || true
  nuclei -l \"\$LIVE\" -t takeover -silent -o \"\$OUTDIR/nuclei_takeover.txt\" || true
else
  echo \"[!] nuclei not found; skipping nuclei scans.\"
fi

if command -v subjack >/dev/null 2>&1; then
  subjack -w \"\$LIVE\" -t \"\$THREADS\" -timeout 30 -ssl -c /dev/null 2>/dev/null | tee \"\$OUTDIR/subjack.txt\" || true
fi
echo -e \"\${GREEN}[+] Nuclei / takeover scans finished\${RESET}\"

####################
# Phase 4: Endpoint collection (gau, waybackurls, hakrawler)
####################
echo -e \"\${YELLOW}[*] Phase 4: Endpoint collection (gau, waybackurls, hakrawler)...\${RESET}\"
ENDPOINTS_RAW=\"\$OUTDIR/endpoints_raw.txt\"
> \"\$ENDPOINTS_RAW\"

if command -v gau >/dev/null 2>&1; then
  gau \"\$TARGET\" >> \"\$ENDPOINTS_RAW\" || true
fi

if command -v waybackurls >/dev/null 2>&1; then
  echo \"\$TARGET\" | waybackurls >> \"\$ENDPOINTS_RAW\" || true
fi

if command -v hakrawler >/dev/null 2>&1; then
  while IFS= read -r host; do
    hakrawler -url \"http://\$host\" -depth 1 -silent >> \"\$ENDPOINTS_RAW\" || true
    hakrawler -url \"https://\$host\" -depth 1 -silent >> \"\$ENDPOINTS_RAW\" || true
  done < \"\$LIVE\"
fi

# keep only http(s) urls and dedupe
grep -Eo \"https?://[^\\\"' ]+\" \"\$ENDPOINTS_RAW\" | sort -u > \"\$OUTDIR/endpoints.txt\" || true
echo -e \"\${GREEN}[+] Collected endpoints: \$(wc -l < \"\$OUTDIR/endpoints.txt\")\${RESET}\"

####################
# Phase 5: Parameter extraction
####################
echo -e \"\${YELLOW}[*] Phase 5: Extract parameterized endpoints (URLs w/ ?)...\${RESET}\"
PARAMS=\"\$OUTDIR/params.txt\"
grep -E \"\\?.+=\" \"\$OUTDIR/endpoints.txt\" | sort -u > \"\$PARAMS\" || true
echo -e \"\${GREEN}[+] Parameterized endpoints: \$(wc -l < \"\$PARAMS\") -> \$PARAMS\${RESET}\"

####################
# Phase 6: Redirect & Reflection quick tests
####################
echo -e \"\${YELLOW}[*] Phase 6: Test parameters for redirects & simple reflections...\${RESET}\"
REDIRECTS=\"\$OUTDIR/redirects.txt\"
REFLECTIONS=\"\$OUTDIR/reflections.txt\"
> \"\$REDIRECTS\"; > \"\$REFLECTIONS\"

while IFS= read -r url; do
  [[ -z \"\$url\" ]] && continue
  marker=\"hydra-\$RANDOM-marker\"
  test_url=\$(echo \"\$url\" | sed -E 's/([?&][^=]+=)[^&]*/\\1'"\$marker"'/' )
  # fetch
  curl -Ls -o /tmp/hydra_resp.txt -w \"%{http_code} %{url_effective}\" --max-redirs 5 --connect-timeout 10 \"\$test_url\" 2>/dev/null || true
  read -r code final_url < <(awk '{print \$1, \$2}' /tmp/hydra_resp.txt 2>/dev/null || echo)
  # redirect test: final_url != requested or 3xx
  if [[ -n \"\$final_url\" && \"\$final_url\" != \"\$test_url\" ]] || [[ \"\$code\" =~ ^3 ]]; then
    echo \"\$url | \$test_url | \$code | \$final_url\" >> \"\$REDIRECTS\"
  fi
  # reflection
  if grep -q \"\$marker\" /tmp/hydra_resp.txt 2>/dev/null; then
    echo \"\$url | \$test_url | REFLECTED\" >> \"\$REFLECTIONS\"
  fi
done < \"\$PARAMS\" || true

echo -e \"\${GREEN}[+] Redirects: \$(wc -l < \"\$REDIRECTS\") reflections: \$(wc -l < \"\$REFLECTIONS\")\${RESET}\"

####################
# Phase 7: Automated sqlmap on parameterized endpoints (CAUTION)
####################
echo -e \"\${YELLOW}[*] Phase 7: Running sqlmap (automated, use with permission)...\${RESET}\"
SQL_OUTPUT_DIR=\"\$OUTDIR/sqlmap\"
mkdir -p \"\$SQL_OUTPUT_DIR\"
if command -v sqlmap >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -z \"\$line\" ]] && continue
    echo \"[*] sqlmap -> \$line\"
    sqlmap -u \"\$line\" \$SQLMAP_OPTS --output-dir=\"\$SQL_OUTPUT_DIR\" --batch --stop-requests=5 || true
  done < \"\$PARAMS\"
else
  echo \"[!] sqlmap not found; skipping SQL tests.\"
fi

echo -e \"\${GREEN}[*] Hydra Recon finished. Outputs in: \$OUTDIR\${RESET}\"
echo \"Key files:\"
echo \" - Subdomains: \$SUBS_RAW\"
echo \" - Live hosts: \$OUTDIR/live_hosts.txt\"
echo \" - Endpoints: \$OUTDIR/endpoints.txt\"
echo \" - Parameterized endpoints: \$PARAMS\"
echo \" - Redirect tests: \$REDIRECTS\"
echo \" - Reflections: \$REFLECTIONS\"
echo \" - Nuclei: \$OUTDIR/nuclei_all.txt and \$OUTDIR/nuclei_takeover.txt\"
echo \" - SQLMap results: \$SQL_OUTPUT_DIR\"
EOF
