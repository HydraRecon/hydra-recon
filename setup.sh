#!/bin/bash

echo "[*] Installing HydraRecon dependencies..."

# Install Go if not installed
if ! command -v go &> /dev/null; then
    echo "[!] Go not found. Installing..."
    sudo apt update
    sudo apt install -y golang
fi

# Update PATH for Go bin
export PATH=$PATH:$(go env GOPATH)/bin

# Install all required Go tools
echo "[*] Installing Go tools..."
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/tomnomnom/assetfinder@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/lc/gau/v2/cmd/gau@latest
go install -v github.com/tomnomnom/waybackurls@latest
go install -v github.com/projectdiscovery/nuclei/v2/cmd/nuclei@latest
go install -v github.com/hakluke/hakrawler@latest
go install github.com/haccer/subjack@latest
go install github.com/tomnomnom/gf@latest

# Install GF patterns
echo "[*] Installing GF patterns..."
mkdir -p ~/.gf
git clone https://github.com/1ndianl33t/Gf-Patterns.git
cp Gf-Patterns/*.json ~/.gf
rm -rf Gf-Patterns

# Final PATH update
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
source ~/.bashrc

echo "[+] HydraRecon setup complete! You can now run ./hydra-recon.sh <domain>"
