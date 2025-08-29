#!/bin/bash
# Zimbra Autodiscover Validator - Production DNS Diagnostic Tool
# 
# Version: 2.1.0
# Repository: git@github.com:JimDunphy/zimbra-autodiscover.git
# 
# Copyright 2025 Mission Critical Email, LLC - All rights reserved.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Author: Mark Stone - Mission Critical Email, LLC
# Ref: https://forums.zimbra.org/viewtopic.php?t=73922
#
# Ref: https://www.missioncriticalemail.com/2025/07/22/autodiscover-records-best-practices-for-zimbra/
#

# Exit on any error, but allow unset variables for arrays
set -eo pipefail

# Version and repository information
readonly VERSION="2.1.0"
readonly REPOSITORY="git@github.com:JimDunphy/zimbra-autodiscover.git"
readonly UPDATE_URL="https://api.github.com/repos/JimDunphy/zimbra-autodiscover/releases/latest"

# Check dependencies
check_dependencies() {
    local missing_deps=()
    for cmd in dig curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "Please install: ${missing_deps[*]}" >&2
        exit 1
    fi
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DIG_TIMEOUT=10
CURL_TIMEOUT=30
MAX_RETRIES=3

# Cache configuration
CACHE_DIR="$HOME/.zimbra-autodiscover/cache"
CACHE_EXPIRY=3600  # 1 hour

# Arrays to track test results
declare -a PASSED_TESTS
declare -a FAILED_TESTS
declare -a NEEDS_INVESTIGATION

# Array to store test details for caching
declare -A TEST_DETAILS

# Input validation functions
validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        echo -e "${RED}Error: Invalid email address format. Please use format: name@domain${NC}" >&2
        return 1
    fi
}

validate_hostname() {
    local hostname="$1"
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?([.]([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?))*$ ]]; then
        echo -e "${RED}Error: Invalid hostname format${NC}" >&2
        return 1
    fi
}

sanitize_input() {
    local input="$1"
    # Remove any characters that could be used for command injection
    echo "$input" | tr -cd '[:alnum:]@._-'
}

# Progress indicator
show_progress() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] $1${NC}"
}

# Network utility functions with retry and timeout
safe_dig() {
    local query_type="$1"
    local query="$2"
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        local result
        if result=$(timeout $DIG_TIMEOUT dig "$query_type" "$query" +short 2>/dev/null || true); then
            echo "$result"
            return 0
        fi
        ((retries++))
        [ $retries -lt $MAX_RETRIES ] && sleep 1
    done
    echo ""  # Return empty string on failure
    return 1
}

safe_curl() {
    local url="$1"
    shift
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        local result
        # Add SSL certificate validation and security options, but don't fail on SSL errors for testing
        if result=$(timeout $CURL_TIMEOUT curl -s --connect-timeout 10 --max-time $CURL_TIMEOUT \
            --fail-with-body --location --max-redirs 3 \
            "$@" "$url" 2>/dev/null || true); then
            echo "$result"
            return 0
        fi
        ((retries++))
        [ $retries -lt $MAX_RETRIES ] && sleep 2
    done
    echo ""  # Return empty string on failure
    return 1
}

# DNS testing functions
test_dns_srv() {
    local service="$1"
    local domain="$2"
    local test_name="$3"
    
    show_progress "Testing SRV record: $service"
    local result
    result=$(safe_dig SRV "_${service}._tcp.$domain" || echo "")
    if [ -n "$result" ] && [ "$result" != " " ]; then
        echo "$result"
        add_test_result "$test_name" "PASS"
    else
        echo "No SRV record found"
        add_test_result "$test_name" "FAIL"
    fi
}

test_dns_txt() {
    local service="$1"
    local domain="$2"
    local test_name="$3"
    
    show_progress "Testing TXT record: $service"
    local result
    result=$(safe_dig TXT "_${service}._tcp.$domain" || echo "")
    if [ -n "$result" ] && [ "$result" != " " ]; then
        echo "$result"
        add_test_result "$test_name" "PASS"
    else
        echo "No TXT record found"
        add_test_result "$test_name" "FAIL"
    fi
}

test_dns_cname() {
    local subdomain="$1"
    local domain="$2"
    local test_name="$3"
    
    show_progress "Testing CNAME record: $subdomain"
    local result
    result=$(safe_dig CNAME "$subdomain.$domain" || echo "")
    if [ -n "$result" ] && [ "$result" != " " ]; then
        echo "$result"
        add_test_result "$test_name" "PASS"
    else
        echo "No CNAME record found"
        add_test_result "$test_name" "FAIL"
    fi
}

test_http_endpoint() {
    local url="$1"
    local test_name="$2"
    local expected_codes="$3"
    
    show_progress "Testing HTTP endpoint: $url"
    local result
    result=$(safe_curl "$url" -I | head -1 || echo "HTTP request failed")
    echo "$result"
    if [[ "$result" =~ $expected_codes ]]; then
        add_test_result "$test_name" "PASS"
    elif [[ "$result" =~ "404" ]] || [[ "$result" == "HTTP request failed" ]]; then
        add_test_result "$test_name" "FAIL"
    else
        add_test_result "$test_name" "INVESTIGATE"
    fi
}

# Function to add test result
add_test_result() {
local test_name="$1"
local status="$2"
local result="${3:-}"

case $status in
"PASS") PASSED_TESTS+=("$test_name") ;;
"FAIL") FAILED_TESTS+=("$test_name") ;;
"INVESTIGATE") NEEDS_INVESTIGATION+=("$test_name") ;;
esac

# Store test details for caching
TEST_DETAILS["$test_name"]="$status|$result"
}

# Cache management functions
ensure_cache_dir() {
    mkdir -p "$CACHE_DIR"
}

get_cache_file() {
    local domain="$1"
    echo "$CACHE_DIR/${domain}.json"
}

is_cache_valid() {
    local cache_file="$1"
    if [ -f "$cache_file" ]; then
        local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        local current_time=$(date +%s)
        [ $((current_time - cache_time)) -lt $CACHE_EXPIRY ]
    else
        return 1
    fi
}

save_cache() {
    local domain="$1"
    local mail_server="$2"
    local cache_file="$3"
    
    ensure_cache_dir
    
    cat > "$cache_file" << EOF
{
  "domain": "$domain",
  "mail_server": "$mail_server", 
  "timestamp": "$(date -Iseconds)",
  "tests": {
EOF
    
    local first=true
    for test_name in "${!TEST_DETAILS[@]}"; do
        [ "$first" = false ] && echo ","
        local status=$(echo "${TEST_DETAILS[$test_name]}" | cut -d'|' -f1)
        local result=$(echo "${TEST_DETAILS[$test_name]}" | cut -d'|' -f2-)
        echo -n "    \"$test_name\": {\"status\": \"$status\", \"result\": \"$result\"}"
        first=false
    done >> "$cache_file"
    
    cat >> "$cache_file" << EOF

  }
}
EOF
}

load_cache() {
    local cache_file="$1"
    
    if ! is_cache_valid "$cache_file"; then
        return 1
    fi
    
    # Parse cached results using basic text processing
    while IFS= read -r line; do
        if [[ "$line" =~ \"([^\"]+)\":[[:space:]]*\{\"status\":[[:space:]]*\"([^\"]+)\" ]]; then
            local test_name="${BASH_REMATCH[1]}"
            local status="${BASH_REMATCH[2]}"
            
            case $status in
                "PASS") PASSED_TESTS+=("$test_name") ;;
                "FAIL") FAILED_TESTS+=("$test_name") ;;
                "INVESTIGATE") NEEDS_INVESTIGATION+=("$test_name") ;;
            esac
        fi
    done < "$cache_file"
    
    return 0
}

# DNS Provider Management Functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DNS_API_DIR="$SCRIPT_DIR/dnsapi"

list_dns_providers() {
    echo "Available DNS Providers:"
    echo ""
    
    if [ -d "$DNS_API_DIR" ]; then
        for provider_file in "$DNS_API_DIR"/dns_*.sh; do
            if [ -f "$provider_file" ]; then
                local provider=$(basename "$provider_file" .sh | sed 's/dns_//')
                source "$provider_file"
                
                # Get provider info if available
                local name="$provider"
                local desc="No description available"
                
                # Try to get PROVIDER_NAME and PROVIDER_DESCRIPTION from sourced file
                if [ -n "$PROVIDER_NAME" ]; then
                    name="$PROVIDER_NAME"
                fi
                if [ -n "$PROVIDER_DESCRIPTION" ]; then
                    desc="$PROVIDER_DESCRIPTION"
                fi
                
                echo "  $provider - $name"
                echo "    $desc"
                echo ""
            fi
        done
    else
        echo "No DNS providers directory found at: $DNS_API_DIR"
    fi
}

load_dns_provider() {
    local provider="$1"
    local provider_file="$DNS_API_DIR/dns_${provider}.sh"
    
    if [ ! -f "$provider_file" ]; then
        echo "Error: DNS provider '$provider' not found"
        echo "Available providers:"
        list_dns_providers
        return 1
    fi
    
    source "$provider_file"
    
    # Check if provider is available
    if ! "dns_${provider}_detect" >/dev/null 2>&1; then
        echo "Error: DNS provider '$provider' not properly configured"
        if type "dns_${provider}_help" >/dev/null 2>&1; then
            echo ""
            "dns_${provider}_help"
        fi
        return 1
    fi
    
    echo "Loaded DNS provider: $provider"
    return 0
}

deploy_missing_records() {
    local provider="$1"
    local domain="$2" 
    local mail_server="$3"
    
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        echo "No missing DNS records to deploy"
        return 0
    fi
    
    echo "Deploying missing DNS records using $provider provider..."
    echo ""
    
    local errors=0
    for test in "${FAILED_TESTS[@]}"; do
        case "$test" in
            "DNS SRV _imaps._tcp")
                if ! "dns_${provider}_add" "$domain" "SRV" "_imaps._tcp.$domain" "10 0 993 $mail_server"; then
                    ((errors++))
                fi
                ;;
            "DNS SRV _submission._tcp")  
                if ! "dns_${provider}_add" "$domain" "SRV" "_submission._tcp.$domain" "10 0 587 $mail_server"; then
                    ((errors++))
                fi
                ;;
            "DNS SRV _autodiscover._tcp")
                if ! "dns_${provider}_add" "$domain" "SRV" "_autodiscover._tcp.$domain" "10 0 443 $mail_server"; then
                    ((errors++))
                fi
                ;;
            "DNS CNAME autodiscover")
                if ! "dns_${provider}_add" "$domain" "CNAME" "autodiscover.$domain" "$mail_server"; then
                    ((errors++))
                fi
                ;;
            "DNS SRV _caldavs._tcp")
                if ! "dns_${provider}_add" "$domain" "SRV" "_caldavs._tcp.$domain" "10 0 443 $mail_server"; then
                    ((errors++))
                fi
                ;;
            "DNS SRV _carddavs._tcp")
                if ! "dns_${provider}_add" "$domain" "SRV" "_carddavs._tcp.$domain" "10 0 443 $mail_server"; then
                    ((errors++))
                fi
                ;;
            "DNS TXT _caldavs._tcp")
                if ! "dns_${provider}_add" "$domain" "TXT" "_caldavs._tcp.$domain" "path=/service/dav/home/"; then
                    ((errors++))
                fi
                ;;
            "DNS TXT _carddavs._tcp")
                if ! "dns_${provider}_add" "$domain" "TXT" "_carddavs._tcp.$domain" "path=/service/dav/home/"; then
                    ((errors++))
                fi
                ;;
        esac
    done
    
    echo ""
    if [ $errors -eq 0 ]; then
        echo "✓ Successfully deployed all missing DNS records"
        echo "DNS changes may take a few minutes to propagate"
    else
        echo "✗ Failed to deploy $errors record(s)"
        echo "Check provider configuration and try again"
        return 1
    fi
}

# Generate Action Required summary
generate_action_summary() {
    local domain="$1"
    local mail_server="$2"
    
    # Check if we have any missing records
    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
        return 0  # Nothing to do
    fi
    
    echo ""
    echo -e "${RED}TODO: Add these DNS records to ${domain}:${NC}"
    echo ""
    
    # Generate the missing records in clean format
    for test in "${FAILED_TESTS[@]}"; do
        case "$test" in
            "DNS SRV _imaps._tcp")
                echo "_imaps._tcp.${domain}.        IN  SRV 10 0 993 ${mail_server}."
                ;;
            "DNS SRV _submission._tcp")
                echo "_submission._tcp.${domain}.   IN  SRV 10 0 587 ${mail_server}."
                ;;
            "DNS SRV _autodiscover._tcp")
                echo "_autodiscover._tcp.${domain}. IN  SRV 10 0 443 ${mail_server}."
                ;;
            "DNS CNAME autodiscover")
                echo "autodiscover.${domain}.       IN  CNAME ${mail_server}."
                ;;
            "DNS SRV _caldavs._tcp")
                echo "_caldavs._tcp.${domain}.      IN  SRV 10 0 443 ${mail_server}."
                ;;
            "DNS SRV _carddavs._tcp")
                echo "_carddavs._tcp.${domain}.     IN  SRV 10 0 443 ${mail_server}."
                ;;
            "DNS TXT _caldavs._tcp")
                echo "_caldavs._tcp.${domain}.      IN  TXT \"path=/service/dav/home/\""
                ;;
            "DNS TXT _carddavs._tcp")
                echo "_carddavs._tcp.${domain}.     IN  TXT \"path=/service/dav/home/\""
                ;;
        esac
    done
}

# Parse command line options
QUIET=false
JSON_OUTPUT=false
CONFIG_FILE=""
GENERATE_BIND=false
BIND_ONLY=false
SHOW_EXAMPLES=false
CACHE_ONLY=false
CACHE_REFRESH=false
DEPLOY_PROVIDER=""

show_help() {
    cat << 'EOF'
Zimbra Autodiscover DNS Configuration Validator

USAGE:
    zimbra-autodiscover-validator.sh [OPTIONS]

DESCRIPTION:
    Validates DNS configuration for Zimbra email autodiscovery and generates 
    BIND zone entries. Tests SRV, TXT, and CNAME records plus HTTP/HTTPS endpoints
    for proper email client autoconfiguration.

OPTIONS:
    -q, --quiet             Suppress progress messages
    -j, --json              Output results in JSON format
    -c, --config FILE       Use configuration file
    -g, --generate          Generate BIND zone entries after validation
    -b, --bind-zone         Generate BIND zone entries only (no validation)
    -e, --example-config    Generate example configuration file
    --cache-only            Use cached results without re-testing DNS
    --cache-refresh         Force refresh cache and re-test everything
    --deploy PROVIDER       Deploy missing DNS records using provider (cloudflare, aws, bind)
    --list-providers        Show available DNS deployment providers
    --no-auth               Skip authentication prompt (DNS validation only)
    -v, --version           Show version information
    --check-updates         Check for available updates
    --update                Update script from GitHub repository
    -h, --help              Show this help message

EXAMPLES:
    # Interactive validation
    ./zimbra-autodiscover-validator.sh

    # Quiet mode with JSON output
    ./zimbra-autodiscover-validator.sh --quiet --json

    # Generate BIND zone entries
    ./zimbra-autodiscover-validator.sh --generate

    # Use configuration file
    ./zimbra-autodiscover-validator.sh --config myconfig.conf

    # Generate zone entries only
    ./zimbra-autodiscover-validator.sh --bind-zone

    # Create example config
    ./zimbra-autodiscover-validator.sh --example-config > config.conf

    # Use cached results for faster deployment
    ./zimbra-autodiscover-validator.sh --cache-only --deploy cloudflare

    # Deploy missing records to AWS Route53
    ./zimbra-autodiscover-validator.sh --deploy aws
    
    # Skip authentication prompt for automation
    ./zimbra-autodiscover-validator.sh --no-auth
    
    # DNS validation only (fastest)
    ./zimbra-autodiscover-validator.sh --no-auth --cache-only

AUTHENTICATION TESTING:
    The tool can optionally test actual email services with your password:
    - ActiveSync autodiscover XML responses
    - CalDAV/CardDAV WebDAV authentication
    - End-to-end service validation
    
    Skip with --no-auth for DNS-only testing (recommended for automation).

CONFIGURATION FILE FORMAT:
    EMAIL="user@example.com"
    MAIL_SERVER="mail.example.com" 
    DOMAIN="example.com"
    
    # Optional authenticated testing (leave as placeholder to skip):
    PASSWORD="your-password"        # DNS validation only  
    PASSWORD="actual-password123"   # DNS + service validation
    
    # Optional timeouts:
    DIG_TIMEOUT=15
    CURL_TIMEOUT=45
    MAX_RETRIES=5

TESTED RECORDS:
    SRV Records: _imaps, _submission, _autodiscover, _caldavs, _carddavs
    TXT Records: CalDAV/CardDAV path information
    CNAME Records: autodiscover.domain.com
    HTTP Endpoints: autodiscover.xml, autoconfig.xml, .well-known URIs

SECURITY FEATURES:
    - Secure credential handling (no password exposure)
    - SSL/TLS certificate validation
    - Input sanitization and validation
    - Configurable timeouts and retry logic

EOF
}

show_example_config() {
    cat << 'EOF'
# Zimbra Autodiscover Validator Configuration
# Save as: config.conf and use with --config option

# Required settings
EMAIL="user@example.com"
MAIL_SERVER="mail.example.com"
DOMAIN="example.com"

# Optional: Override default timeouts (seconds)
DIG_TIMEOUT=10
CURL_TIMEOUT=30
MAX_RETRIES=3

# Optional: Suppress colored output
NO_COLOR=false

# Optional: Default to quiet mode
QUIET=false
EOF
}

show_version() {
    echo "Zimbra Autodiscover Validator v$VERSION"
    echo "Repository: $REPOSITORY"
}

check_for_updates() {
    echo "Checking for updates..."
    
    if ! command -v curl >/dev/null 2>&1; then
        echo "curl required for update checking"
        return 1
    fi
    
    local latest_info
    if ! latest_info=$(curl -s --max-time 10 "$UPDATE_URL" 2>/dev/null); then
        echo "Unable to check for updates (network error)"
        return 1
    fi
    
    local latest_version
    if command -v jq >/dev/null 2>&1; then
        latest_version=$(echo "$latest_info" | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
    else
        # Fallback parsing without jq
        latest_version=$(echo "$latest_info" | grep -o '"tag_name":"[^"]*' | cut -d'"' -f4 | sed 's/^v//')
    fi
    
    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo "Unable to determine latest version"
        return 1
    fi
    
    echo "Current version: $VERSION"
    echo "Latest version:  $latest_version"
    
    if [ "$VERSION" = "$latest_version" ]; then
        echo "✓ You are running the latest version"
    else
        echo "⚠ Update available!"
        echo ""
        echo "To update:"
        echo "  git clone $REPOSITORY"
        echo "  cd zimbra-autodiscover"
        echo "  chmod +x zimbra-autodiscover-validator.sh"
        echo ""
        echo "Or download latest release:"
        echo "  https://github.com/JimDunphy/zimbra-autodiscover/releases/latest"
    fi
}

update_script() {
    echo "Updating Zimbra Autodiscover Validator..."
    
    # Check if we're in a git repository
    if [ -d ".git" ] && command -v git >/dev/null 2>&1; then
        echo "Detected git repository - pulling latest changes..."
        
        # Stash any local changes
        if ! git diff --quiet; then
            echo "Stashing local changes..."
            git stash push -m "Auto-stash before update $(date)"
        fi
        
        # Pull latest changes
        if git pull origin main; then
            chmod +x zimbra-autodiscover-validator.sh
            echo "✓ Update completed successfully"
            echo "✓ Script permissions restored"
            
            # Show new version
            echo ""
            show_version
        else
            echo "✗ Git pull failed"
            return 1
        fi
    else
        echo "Not in a git repository. Please update manually:"
        echo "  git clone $REPOSITORY"
        echo "  cd zimbra-autodiscover"
        echo "  chmod +x zimbra-autodiscover-validator.sh"
        return 1
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -j|--json)
            JSON_OUTPUT=true
            shift
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -g|--generate)
            GENERATE_BIND=true
            shift
            ;;
        -b|--bind-zone)
            BIND_ONLY=true
            shift
            ;;
        -e|--example-config)
            show_example_config
            exit 0
            ;;
        --cache-only)
            CACHE_ONLY=true
            shift
            ;;
        --cache-refresh)
            CACHE_REFRESH=true
            shift
            ;;
        --deploy)
            DEPLOY_PROVIDER="$2"
            shift 2
            ;;
        --list-providers)
            list_dns_providers
            exit 0
            ;;
        --no-auth)
            SKIP_AUTH_PROMPT=true
            shift
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        --check-updates)
            check_for_updates
            exit 0
            ;;
        --update)
            update_script
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Override progress function for quiet mode
if [ "$QUIET" = true ]; then
    show_progress() {
        : # Do nothing in quiet mode
    }
fi

# Check dependencies first
check_dependencies

# Load config file if provided
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# BIND zone generation function
generate_bind_zone() {
    local domain="$1"
    local mail_server="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat << EOF
; Zimbra Autodiscover DNS Records for ${domain}
; Generated on ${timestamp}
; 
; Add these records to your BIND zone file for ${domain}

; SRV Records for Email Services
_imaps._tcp.${domain}.           IN  SRV 10 0 993  ${mail_server}.
_submission._tcp.${domain}.      IN  SRV 10 0 587  ${mail_server}.
_autodiscover._tcp.${domain}.    IN  SRV 10 0 443  ${mail_server}.
_caldavs._tcp.${domain}.         IN  SRV 10 0 443  ${mail_server}.
_carddavs._tcp.${domain}.        IN  SRV 10 0 443  ${mail_server}.

; TXT Records for DAV Service Paths
_caldavs._tcp.${domain}.         IN  TXT "path=/service/dav/home/"
_carddavs._tcp.${domain}.        IN  TXT "path=/service/dav/home/"

; CNAME Records for Autodiscover Services
autodiscover.${domain}.          IN  CNAME ${mail_server}.
autoconfig.${domain}.            IN  CNAME ${mail_server}.

; Optional: MX Record (if not already present)
; ${domain}.                     IN  MX   10 ${mail_server}.

; Optional: A Record for mail server (if not in different zone)
; ${mail_server}.                IN  A    192.168.1.100

;
; Notes:
; - Adjust priorities (10) and ports as needed for your setup
; - Ensure ${mail_server} resolves to correct IP address
; - Test configuration after DNS propagation (up to 48 hours)
; - Use 'dig SRV _imaps._tcp.${domain}' to verify SRV records
;
EOF
}

# Handle BIND zone generation only mode
if [ "$BIND_ONLY" = true ]; then
    if [ -n "$DOMAIN" ] && [ -n "$MAIL_SERVER" ]; then
        # Use values from config file
        generate_bind_zone "$DOMAIN" "$MAIL_SERVER"
    else
        # Prompt for values
        echo "BIND Zone Generator for Zimbra Autodiscover"
        echo "=========================================="
        echo -n "Enter domain name (e.g. example.com): "
        read DOMAIN
        DOMAIN=$(sanitize_input "$DOMAIN")
        validate_hostname "$DOMAIN"
        
        echo -n "Enter mail server hostname (e.g. mail.example.com): "
        read MAIL_SERVER
        MAIL_SERVER=$(sanitize_input "$MAIL_SERVER")
        validate_hostname "$MAIL_SERVER"
        
        echo ""
        generate_bind_zone "$DOMAIN" "$MAIL_SERVER"
    fi
    exit 0
fi

# Handle deployment mode
if [ -n "$DEPLOY_PROVIDER" ]; then
    if ! load_dns_provider "$DEPLOY_PROVIDER"; then
        exit 1
    fi
fi

# Prompt user for email address only if not provided in config
echo -e "${BLUE}Zimbra Autodiscover DNS Configuration Validator${NC}"
echo "============================================="

if [ -z "$EMAIL" ]; then
    echo -n "Enter email address (name@domain): "
    read EMAIL
    EMAIL=$(sanitize_input "$EMAIL")
fi

# Validate email format
validate_email "$EMAIL"

# Extract username and domain
USERNAME=$(echo "$EMAIL" | cut -d'@' -f1)
DOMAIN=$(echo "$EMAIL" | cut -d'@' -f2)

# Ask for mail server hostname only if not provided in config
if [ -z "$MAIL_SERVER" ]; then
    echo -n "Enter mail server hostname (e.g. mail.domain.com, imap.domain.com): "
    read MAIL_SERVER
    MAIL_SERVER=$(sanitize_input "$MAIL_SERVER")
fi

# Validate mail server format
validate_hostname "$MAIL_SERVER"

# Handle cache logic
CACHE_FILE=$(get_cache_file "$DOMAIN")

if [ "$CACHE_ONLY" = true ]; then
    echo "Using cached results for $DOMAIN..."
    if ! load_cache "$CACHE_FILE"; then
        echo "No valid cache found for $DOMAIN. Run without --cache-only first."
        exit 1
    fi
    echo "Loaded cached results"
elif [ "$CACHE_REFRESH" = true ]; then
    echo "Forcing cache refresh for $DOMAIN..."
    rm -f "$CACHE_FILE"
else
    # Try to load cache if available and valid
    if load_cache "$CACHE_FILE" 2>/dev/null; then
        echo "Using cached results (cache is fresh)"
        CACHE_LOADED=true
    fi
fi

# Ask for password only in interactive mode (no config file)
if [ -z "$CONFIG_FILE" ] && [ "$CACHE_ONLY" != true ]; then
    echo -n "Enter password for $EMAIL (press Enter to skip authenticated validation): "
    
    if read -s PASSWORD && [ -n "$PASSWORD" ]; then
        # Create secure credential function for curl that doesn't expose credentials
        get_auth_header() {
            local temp_creds="$EMAIL:$PASSWORD"
            echo -n "$temp_creds" | base64
            unset temp_creds
        }
        AUTHENTICATED=true
        unset PASSWORD  # Remove from environment immediately
    else
        AUTHENTICATED=false
    fi
    echo
else
    # Non-interactive mode - check if PASSWORD properly set in config file
    if [ -n "$PASSWORD" ] && [ "$PASSWORD" != "your-password" ] && [ "$PASSWORD" != "CHANGE_ME" ] && [ "$PASSWORD" != "" ]; then
        get_auth_header() {
            local temp_creds="$EMAIL:$PASSWORD"
            echo -n "$temp_creds" | base64
            unset temp_creds
        }
        AUTHENTICATED=true
    else
        AUTHENTICATED=false
    fi
fi

echo ""
echo -e "${BLUE}Validating autodiscover DNS configuration for $DOMAIN${NC}"
echo "Username: $USERNAME"
echo "Domain: $DOMAIN"
echo "Mail Server: $MAIL_SERVER"
echo "============================================="

# Skip testing if we loaded cache
if [ "$CACHE_LOADED" != true ] && [ "$CACHE_ONLY" != true ]; then

echo -e "${BLUE}1. DNS SRV Records:${NC}"
echo "IMAPS:"
test_dns_srv "imaps" "$DOMAIN" "DNS SRV _imaps._tcp"

echo "SUBMISSION:"
test_dns_srv "submission" "$DOMAIN" "DNS SRV _submission._tcp"

echo "AUTODISCOVER:"
test_dns_srv "autodiscover" "$DOMAIN" "DNS SRV _autodiscover._tcp"

echo "CalDAV:"
test_dns_srv "caldavs" "$DOMAIN" "DNS SRV _caldavs._tcp"

echo "CardDAV:"
test_dns_srv "carddavs" "$DOMAIN" "DNS SRV _carddavs._tcp"

echo -e "\n${BLUE}2. DNS TXT Records (DAV paths):${NC}"
echo "CalDAV path:"
test_dns_txt "caldavs" "$DOMAIN" "DNS TXT _caldavs._tcp"

echo "CardDAV path:"
test_dns_txt "carddavs" "$DOMAIN" "DNS TXT _carddavs._tcp"

echo -e "\n${BLUE}3. DNS CNAME Records:${NC}"
echo "Autodiscover CNAME:"
test_dns_cname "autodiscover" "$DOMAIN" "DNS CNAME autodiscover"

echo -e "\n${BLUE}4. Autodiscover Service Availability:${NC}"
echo "ActiveSync/Exchange autodiscover endpoint:"
test_http_endpoint "https://autodiscover.$DOMAIN/autodiscover/autodiscover.xml" "ActiveSync Autodiscover Service" "200|401|405"

echo "Thunderbird autoconfig endpoint:"
test_http_endpoint "https://autoconfig.$DOMAIN/mail/config-v1.1.xml" "Thunderbird Autoconfig Service" "200"

echo -e "\n${BLUE}5. Well-known URI Discovery:${NC}"
echo "CardDAV well-known URI:"
test_http_endpoint "https://$MAIL_SERVER/.well-known/carddav" "CardDAV Well-known URI" "301|302|200"

echo "CalDAV well-known URI:"
test_http_endpoint "https://$MAIL_SERVER/.well-known/caldav" "CalDAV Well-known URI" "301|302|200"

echo -e "\n${BLUE}6. DAV Service Discovery:${NC}"
echo "DAV service endpoint availability:"
test_http_endpoint "https://$MAIL_SERVER/service/dav/home/" "DAV Service Discovery" "200|401|405"

# Optional authenticated validation
if [ "$AUTHENTICATED" = true ]; then
echo -e "\n${BLUE}7. Authenticated Service Validation:${NC}"

echo "Testing ActiveSync autodiscover response format..."
ACTIVESYNC_AUTH_RESPONSE=$(safe_curl "https://autodiscover.$DOMAIN/autodiscover/autodiscover.xml" \
-H "Authorization: Basic $(get_auth_header)" -X POST \
-H "Content-Type: text/xml; charset=utf-8" \
-d "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<Autodiscover xmlns=\"http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006\">
<Request>
<EMailAddress>$EMAIL</EMailAddress>
<AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006</AcceptableResponseSchema>
</Request>
</Autodiscover>")

if [[ "$ACTIVESYNC_AUTH_RESPONSE" =~ "Autodiscover" ]] && [[ ! "$ACTIVESYNC_AUTH_RESPONSE" =~ "401" ]]; then
echo "ActiveSync response contains proper XML structure"
add_test_result "ActiveSync Response Format" "PASS"
elif [[ "$ACTIVESYNC_AUTH_RESPONSE" =~ "401" ]]; then
echo "ActiveSync authentication failed - check credentials"
add_test_result "ActiveSync Response Format" "FAIL"
else
echo "ActiveSync response format unexpected"
add_test_result "ActiveSync Response Format" "INVESTIGATE"
fi

echo "Testing CardDAV service response..."
CARDDAV_AUTH_RESPONSE=$(safe_curl "https://$MAIL_SERVER/service/dav/home/" \
-H "Authorization: Basic $(get_auth_header)" -X PROPFIND \
-H "Depth: 0" \
-H "Content-Type: text/xml" \
-d "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<propfind xmlns=\"DAV:\">
<prop>
<resourcetype/>
</prop>
</propfind>")

if [[ "$CARDDAV_AUTH_RESPONSE" =~ "multistatus" ]]; then
echo "CardDAV service responding with proper DAV XML"
add_test_result "CardDAV Service Response" "PASS"
elif [[ "$CARDDAV_AUTH_RESPONSE" =~ "401" ]]; then
echo "CardDAV authentication failed - check credentials"
add_test_result "CardDAV Service Response" "FAIL"
else
echo "CardDAV service response unexpected"
add_test_result "CardDAV Service Response" "INVESTIGATE"
fi

echo "Testing CalDAV service response..."
CALDAV_AUTH_RESPONSE=$(safe_curl "https://$MAIL_SERVER/service/dav/home/" \
-H "Authorization: Basic $(get_auth_header)" -X PROPFIND \
-H "Depth: 0" \
-H "Content-Type: text/xml" \
-d "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<propfind xmlns=\"DAV:\">
<prop>
<resourcetype/>
</prop>
</propfind>")

if [[ "$CALDAV_AUTH_RESPONSE" =~ "multistatus" ]]; then
echo "CalDAV service responding with proper DAV XML"
add_test_result "CalDAV Service Response" "PASS"
elif [[ "$CALDAV_AUTH_RESPONSE" =~ "401" ]]; then
echo "CalDAV authentication failed - check credentials"
add_test_result "CalDAV Service Response" "FAIL"
else
echo "CalDAV service response unexpected"
add_test_result "CalDAV Service Response" "INVESTIGATE"
fi
fi

# End of testing section - save cache if we just ran tests
if [ "$CACHE_LOADED" != true ] && [ "$CACHE_ONLY" != true ]; then
    save_cache "$DOMAIN" "$MAIL_SERVER" "$CACHE_FILE"
fi

fi  # End of main testing block from line 826

# Generate summary report
generate_json_report() {
    local timestamp=$(date -Iseconds)
    local needs_count=0
    [ ${#NEEDS_INVESTIGATION[@]} -gt 0 ] 2>/dev/null && needs_count=${#NEEDS_INVESTIGATION[@]}
    local total_tests=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]} + needs_count))
    
    # Handle empty arrays safely for JSON
    local passed_json="[]"
    local failed_json="[]"
    local investigate_json="[]"
    
    [ ${#PASSED_TESTS[@]} -gt 0 ] && passed_json=$(printf '%s\n' "${PASSED_TESTS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
    [ ${#FAILED_TESTS[@]} -gt 0 ] && failed_json=$(printf '%s\n' "${FAILED_TESTS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
    [ ${#NEEDS_INVESTIGATION[@]} -gt 0 ] 2>/dev/null && investigate_json=$(printf '%s\n' "${NEEDS_INVESTIGATION[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]')
    
    cat << EOF
{
    "timestamp": "$timestamp",
    "domain": "$DOMAIN",
    "email": "$EMAIL",
    "mail_server": "$MAIL_SERVER",
    "summary": {
        "total_tests": $total_tests,
        "passed": ${#PASSED_TESTS[@]},
        "failed": ${#FAILED_TESTS[@]},
        "needs_investigation": $needs_count
    },
    "results": {
        "passed": $passed_json,
        "failed": $failed_json,
        "needs_investigation": $investigate_json
    },
    "status": $(
        if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
            echo '"complete"'
        elif [ ${#FAILED_TESTS[@]} -le 2 ]; then
            echo '"mostly_configured"'
        else
            echo '"incomplete"'
        fi
    )
}
EOF
}

if [ "$JSON_OUTPUT" = true ]; then
    generate_json_report
else
    echo -e "\n${BLUE}=============================================${NC}"
    echo -e "${BLUE}ZIMBRA AUTODISCOVER DNS VALIDATION REPORT${NC}"
    echo -e "${BLUE}=============================================${NC}"

    if [ ${#PASSED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${GREEN}✓ DNS CONFIGURATION VALIDATED (${#PASSED_TESTS[@]}):${NC}"
    for test in "${PASSED_TESTS[@]}"; do
    echo -e " ${GREEN}✓${NC} $test"
    done
    fi

    if [ ${#NEEDS_INVESTIGATION[@]} -gt 0 ] 2>/dev/null; then
    echo -e "\n${YELLOW}⚠ NEEDS REVIEW (${#NEEDS_INVESTIGATION[@]}):${NC}"
    for test in "${NEEDS_INVESTIGATION[@]}"; do
    echo -e " ${YELLOW}⚠${NC} $test"
    done
    echo -e " ${YELLOW}Note: These may be working but require manual verification${NC}"
    fi

    if [ ${#FAILED_TESTS[@]} -gt 0 ]; then
    echo -e "\n${RED}✗ DNS CONFIGURATION MISSING (${#FAILED_TESTS[@]}):${NC}"
    for test in "${FAILED_TESTS[@]}"; do
    echo -e " ${RED}✗${NC} $test"
    done
    fi

    # Overall assessment  
    needs_count=0
    [ ${#NEEDS_INVESTIGATION[@]} -gt 0 ] 2>/dev/null && needs_count=${#NEEDS_INVESTIGATION[@]}
    TOTAL_TESTS=$((${#PASSED_TESTS[@]} + ${#FAILED_TESTS[@]} + needs_count))
    CONFIGURED_ITEMS=$((${#PASSED_TESTS[@]} + needs_count))

    echo -e "\n${BLUE}DNS CONFIGURATION SUMMARY:${NC}"
    echo "Total autodiscover components tested: $TOTAL_TESTS"
    echo "Properly configured: ${#PASSED_TESTS[@]}"
    echo "Need review: $needs_count"
    echo "Missing configuration: ${#FAILED_TESTS[@]}"

    if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo -e "\n${GREEN}✓ AUTODISCOVER DNS CONFIGURATION COMPLETE${NC}"
    echo -e "All required DNS records are properly configured for Zimbra autodiscovery."
    elif [ ${#FAILED_TESTS[@]} -le 2 ]; then
    echo -e "\n${YELLOW}⚠ AUTODISCOVER MOSTLY CONFIGURED${NC}"
    echo -e "Core autodiscover functionality available, minor items need attention."
    else
    echo -e "\n${RED}✗ AUTODISCOVER CONFIGURATION INCOMPLETE${NC}"
    echo -e "Multiple DNS records missing - clients may have difficulty with automatic setup."
    fi

    echo -e "\n${BLUE}Zimbra autodiscover DNS validation complete.${NC}"
    
    # Generate Action Required summary if there are failed tests
    generate_action_summary "$DOMAIN" "$MAIL_SERVER"
fi

# Generate BIND zone entries if requested
if [ "$GENERATE_BIND" = true ]; then
    echo ""
    echo -e "${BLUE}=============================================${NC}"
    echo -e "${BLUE}BIND ZONE ENTRIES${NC}"
    echo -e "${BLUE}=============================================${NC}"
    echo ""
    generate_bind_zone "$DOMAIN" "$MAIL_SERVER"
    echo ""
    echo -e "${YELLOW}Note: Add these entries to your BIND zone file and reload DNS${NC}"
    echo -e "${YELLOW}Test with: dig SRV _imaps._tcp.$DOMAIN${NC}"
fi

# Deploy missing records if provider specified
if [ -n "$DEPLOY_PROVIDER" ]; then
    echo ""
    deploy_missing_records "$DEPLOY_PROVIDER" "$DOMAIN" "$MAIL_SERVER"
fi
