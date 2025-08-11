#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

DOMAIN=$1
OUTPUT="recon-$DOMAIN"
mkdir -p "$OUTPUT"

echo "[*] Starting HydraRecon on $DOMAIN..."
echo "[*] Output folder: $OUTPUT"

# 1. Subdomain Enumeration
echo "[1/10] Running subfinder..."
subfinder -d "$DOMAIN" -o "$OUTPUT/subfinder.txt"

echo "[2/10] Running assetfinder..."
assetfinder --subs-only "$DOMAIN" > "$OUTPUT/assetfinder.txt"

# Merge and clean subdomains
cat "$OUTPUT/subfinder.txt" "$OUTPUT/assetfinder.txt" | sort -u > "$OUTPUT/all_subdomains.txt"

# 2. Live Host Detection
echo "[3/10] Probing live hosts with httpx..."
httpx -l "$OUTPUT/all_subdomains.txt" -o "$OUTPUT/live_hosts.txt"

# 3. Subdomain Takeover
echo "[4/10] Checking for subdomain takeover with subjack..."
subjack -w "$OUTPUT/all_subdomains.txt" -o "$OUTPUT/takeover.txt" -ssl

# 4. Crawling & Gathering URLs
echo "[5/10] Running gau..."
gau "$DOMAIN" > "$OUTPUT/gau.txt"

echo "[6/10] Running waybackurls..."
waybackurls "$DOMAIN" > "$OUTPUT/waybackurls.txt"

echo "[7/10] Running hakrawler..."
cat "$OUTPUT/live_hosts.txt" | hakrawler > "$OUTPUT/hakrawler.txt"

# Merge and clean URLs
cat "$OUTPUT/gau.txt" "$OUTPUT/waybackurls.txt" "$OUTPUT/hakrawler.txt" | sort -u > "$OUTPUT/all_urls.txt"

# 5. Parameter Extraction
echo "[8/10] Extracting parameters..."
grep "=" "$OUTPUT/all_urls.txt" | sort -u > "$OUTPUT/params.txt"

# 6. GF Pattern Matching
echo "[9/10] Checking for vulnerabilities with gf..."
gf sqli < "$OUTPUT/params.txt" > "$OUTPUT/sqli.txt"
gf xss < "$OUTPUT/params.txt" > "$OUTPUT/xss.txt"
gf lfi < "$OUTPUT/params.txt" > "$OUTPUT/lfi.txt"
gf redirect < "$OUTPUT/params.txt" > "$OUTPUT/redirect.txt"

# 7. Nuclei Scanning
echo "[10/10] Running nuclei scan..."
nuclei -l "$OUTPUT/live_hosts.txt" -o "$OUTPUT/nuclei.txt"

echo "[+] HydraRecon complete. Results saved in $OUTPUT/"
