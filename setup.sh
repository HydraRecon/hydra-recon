cat > setup.sh <<'EOF'
#!/usr/bin/env bash
# setup helper - installs common tools used by hydra-recon
set -e
echo "[*] Installing prerequisites (apt)..."
sudo apt update
sudo apt install -y git curl wget jq build-essential golang-go

export GOPATH=\${GOPATH:-\$HOME/go}
export PATH=\$PATH:\$GOPATH/bin

echo "[*] Installing common recon tools (subfinder, httpx, gau, waybackurls, nuclei)..."
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/tomnomnom/assetfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/lc/gau/v2/cmd/gau@latest
go install -v github.com/tomnomnom/waybackurls@latest
go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest
go install -v github.com/hakluke/hakrawler@latest
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/haccer/subjack@latest
go install github.com/tomnomnom/waybackurls@latest
go install github.com/tomnomnom/gf@latest

echo "[*] Cloning sqlmap (if you want sqlmap in PATH, add it manually or use pip)"
if [[ ! -d sqlmap ]]; then
  git clone --depth 1 https://github.com/sqlmapproject/sqlmap.git
  echo "[*] sqlmap cloned to ./sqlmap (run with python3 sqlmap/sqlmap.py)"
fi

echo "[*] Done. Make sure \$GOPATH/bin is in your PATH (e.g. export PATH=\$PATH:\$GOPATH/bin)"
EOF
