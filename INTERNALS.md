# Zimbra Autodiscover Validator - Internal Architecture

*A comprehensive guide for developers looking to understand, extend, or contribute to the Zimbra Autodiscover Validator.*

## Table of Contents

1. [What is Email Autodiscovery?](#what-is-email-autodiscovery)
2. [How Zimbra Autodiscover Works](#how-zimbra-autodiscover-works)
3. [Script Architecture](#script-architecture)
4. [Core Functions Reference](#core-functions-reference)
5. [DNS Record Types Explained](#dns-record-types-explained)
6. [Caching System](#caching-system)
7. [DNS Provider Plugin System](#dns-provider-plugin-system)
8. [Testing Framework](#testing-framework)
9. [Adding New Features](#adding-new-features)
10. [Troubleshooting Guide](#troubleshooting-guide)
11. [Educational Resources](#educational-resources)

---

## What is Email Autodiscovery?

**Email autodiscovery** is a mechanism that allows email clients (like Outlook, Thunderbird, iOS Mail) to automatically configure themselves when a user enters just their email address and password.

### The Problem It Solves
Without autodiscovery, users must manually enter:
- IMAP/SMTP server addresses 
- Port numbers (993, 587, etc.)
- Security settings (SSL/TLS)
- Authentication methods

### How It Works (Simplified)
1. **User enters**: `john@company.com` 
2. **Client queries DNS** for special records like `_imaps._tcp.company.com`
3. **DNS responds** with server details: `mail.company.com:993`
4. **Client auto-configures** using discovered settings

### Why Zimbra Needs Special Setup
Zimbra requires specific DNS records for different services:
- **IMAP/SMTP** - Basic email access
- **ActiveSync** - Mobile device sync (Exchange-compatible)
- **CalDAV/CardDAV** - Calendar and contact sync
- **Autodiscover** - Microsoft Outlook compatibility

---

## How Zimbra Autodiscover Works

### The Discovery Chain

```
Email Client
    ↓
1. DNS SRV Query: _imaps._tcp.company.com
    ↓
2. DNS Response: 10 0 993 mail.company.com
    ↓ 
3. HTTPS Request: https://autodiscover.company.com/autodiscover/autodiscover.xml
    ↓
4. XML Response: Server configuration details
    ↓
5. Client Configures: IMAP=mail.company.com:993, SMTP=mail.company.com:587
```

### Required DNS Records

| Record Type | Name | Value | Purpose |
|-------------|------|-------|---------|
| SRV | `_imaps._tcp` | `10 0 993 mail.company.com.` | IMAP over SSL |
| SRV | `_submission._tcp` | `10 0 587 mail.company.com.` | SMTP submission |
| SRV | `_autodiscover._tcp` | `10 0 443 mail.company.com.` | Exchange autodiscover |
| SRV | `_caldavs._tcp` | `10 0 443 mail.company.com.` | Calendar sync |
| SRV | `_carddavs._tcp` | `10 0 443 mail.company.com.` | Contact sync |
| TXT | `_caldavs._tcp` | `"path=/service/dav/home/"` | CalDAV endpoint path |
| TXT | `_carddavs._tcp` | `"path=/service/dav/home/"` | CardDAV endpoint path |
| CNAME | `autodiscover` | `mail.company.com.` | Autodiscover endpoint |

---

## Script Architecture

### High-Level Flow

```
main()
├── parse_arguments()
├── load_config_file()
├── check_dependencies()
├── cache_management()
│   ├── load_cache() → Skip testing if fresh
│   └── save_cache() → Store results for reuse
├── dns_validation_loop()
│   ├── test_dns_srv()
│   ├── test_dns_txt() 
│   ├── test_dns_cname()
│   └── test_http_endpoint()
├── authentication_testing()
│   ├── activesync_validation()
│   ├── caldav_validation()
│   └── carddav_validation()
├── results_processing()
│   ├── generate_json_report()
│   ├── generate_text_report()
│   └── generate_action_summary()
└── output_generation()
    ├── generate_bind_zone()
    └── deploy_missing_records()
```

### Core Data Structures

```bash
# Test result tracking arrays
PASSED_TESTS=()          # Tests that succeeded
FAILED_TESTS=()          # Tests that failed (need DNS records)
NEEDS_INVESTIGATION=()   # Tests with ambiguous results

# Test details associative array 
declare -A TEST_DETAILS  # ["test_name"]="status|result_details"

# Configuration variables
EMAIL=""                 # User's email address
DOMAIN=""               # Domain to test (extracted from EMAIL)
MAIL_SERVER=""          # Zimbra server hostname
PASSWORD=""             # Optional password for authenticated testing
```

### Key Design Decisions

#### 1. **Graceful Failure Handling**
```bash
# WRONG: Abort on first failure
test_dns_srv() {
    dig_result=$(dig +short SRV "_${service}._tcp.${domain}")
    [ -z "$dig_result" ] && exit 1  # ❌ Kills entire script
}

# RIGHT: Continue testing, record failure
test_dns_srv() {
    dig_result=$(safe_dig SRV "_${service}._tcp.${domain}")
    if [ -z "$dig_result" ]; then
        add_test_result "$test_name" "FAIL" "No SRV record found"
        return 1  # ✅ Continue to next test
    fi
}
```

#### 2. **Sequential vs Parallel Execution**
- **Originally parallel** with `&` and `wait` for speed
- **Changed to sequential** because background processes can't modify parent shell arrays
- **Trade-off**: Slower execution but reliable result collection

#### 3. **Secure Credential Handling**
```bash
# Create function that doesn't expose credentials in process list
get_auth_header() {
    local temp_creds="$EMAIL:$PASSWORD"
    echo -n "$temp_creds" | base64
    unset temp_creds  # Immediately clear from memory
}
```

---

## Core Functions Reference

### DNS Testing Functions

#### `test_dns_srv(service, domain, test_name)`
Tests SRV records for email services.

```bash
test_dns_srv() {
    local service="$1"    # "imaps", "submission", etc.
    local domain="$2"     # "company.com" 
    local test_name="$3"  # "DNS SRV _imaps._tcp"
    
    # Query: dig +short SRV _imaps._tcp.company.com
    local dig_result=$(safe_dig SRV "_${service}._tcp.${domain}")
    
    if [ -n "$dig_result" ]; then
        show_progress "$dig_result"
        add_test_result "$test_name" "PASS" "$dig_result"
    else
        add_test_result "$test_name" "FAIL" "No SRV record found"
    fi
}
```

**Expected SRV Format**: `priority weight port target`
**Example**: `10 0 993 mail.company.com.`

#### `test_dns_txt(service, domain, test_name)`
Tests TXT records containing service paths.

```bash
# Tests for: _caldavs._tcp.company.com TXT "path=/service/dav/home/"
```

#### `test_dns_cname(subdomain, domain, test_name)`  
Tests CNAME records for service endpoints.

```bash
# Tests for: autodiscover.company.com CNAME mail.company.com.
```

### HTTP Testing Functions

#### `test_http_endpoint(url, test_name, expected_codes)`
Tests HTTP/HTTPS service availability.

```bash
test_http_endpoint() {
    local url="$1"              # "https://autodiscover.company.com/..."
    local test_name="$2"        # "ActiveSync Autodiscover Service"  
    local expected_codes="$3"   # "200|401|405" (regex pattern)
    
    # Use HEAD request to avoid downloading content
    local response=$(safe_curl "$url" -I -w "%{http_code}")
    local http_code=$(echo "$response" | tail -1)
    
    if [[ "$http_code" =~ $expected_codes ]]; then
        add_test_result "$test_name" "PASS" "HTTP $http_code"
    else
        add_test_result "$test_name" "FAIL" "HTTP $http_code (expected $expected_codes)"
    fi
}
```

### Utility Functions

#### `safe_dig(type, query)`
DNS query with timeout and error handling.

```bash
safe_dig() {
    local type="$1"     # "SRV", "TXT", "CNAME"
    local query="$2"    # "_imaps._tcp.company.com"
    
    timeout "${DIG_TIMEOUT:-10}" dig +short "$type" "$query" 2>/dev/null || echo ""
}
```

#### `safe_curl(url, [options...])`
HTTP request with timeout and retry logic.

```bash
safe_curl() {
    local url="$1"
    shift
    local attempt=1
    
    while [ $attempt -le "${MAX_RETRIES:-3}" ]; do
        if timeout "${CURL_TIMEOUT:-30}" curl -s --max-time 30 "$@" "$url"; then
            return 0
        fi
        ((attempt++))
        sleep 2
    done
    return 1
}
```

---

## DNS Record Types Explained

### SRV Records (Service Records)
**Format**: `_service._protocol.domain TTL IN SRV priority weight port target`

```bash
_imaps._tcp.company.com. 300 IN SRV 10 0 993 mail.company.com.
#     ↑        ↑              ↑  ↑ ↑   ↑
# service  protocol      priority │ │ port
#                        weight ──┘ │ 
#                        target ────┘
```

- **Priority**: Lower = preferred (like MX records)
- **Weight**: Load balancing among same priority 
- **Port**: Service port number
- **Target**: Server hostname

### TXT Records (Text Records)
Store arbitrary text data, used for service configuration.

```bash
_caldavs._tcp.company.com. IN TXT "path=/service/dav/home/"
```

For CalDAV/CardDAV, tells clients the URL path to use.

### CNAME Records (Canonical Name)
Alias one domain name to another.

```bash
autodiscover.company.com. IN CNAME mail.company.com.
```

Redirects `autodiscover.company.com` requests to `mail.company.com`.

---

## Caching System

### Architecture

```
~/.zimbra-autodiscover/cache/
├── company.com.json         # Cached results for company.com
├── example.org.json         # Cached results for example.org  
└── client-domain.json       # Each domain gets its own cache file
```

### Cache File Structure

```json
{
  "domain": "company.com",
  "mail_server": "mail.company.com",
  "timestamp": "2025-08-29T10:15:45-05:00",
  "tests": {
    "DNS SRV _imaps._tcp": {
      "status": "PASS", 
      "result": "10 0 993 mail.company.com."
    },
    "ActiveSync Autodiscover Service": {
      "status": "FAIL",
      "result": "HTTP 404 (expected 200|401|405)"
    }
  }
}
```

### Cache Functions

#### `save_cache(domain, mail_server, cache_file)`
Writes current test results to JSON cache file.

```bash
# Iterate through TEST_DETAILS associative array
for test_name in "${!TEST_DETAILS[@]}"; do
    local status=$(echo "${TEST_DETAILS[$test_name]}" | cut -d'|' -f1)
    local result=$(echo "${TEST_DETAILS[$test_name]}" | cut -d'|' -f2-)
    echo "    \"$test_name\": {\"status\": \"$status\", \"result\": \"$result\"}"
done
```

#### `load_cache(cache_file)`
Parses JSON cache and populates result arrays.

```bash
# Parse JSON using regex (bash-native, no jq dependency)
while read -r line; do
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
```

### Cache Usage Patterns

```bash
# Standard run - cache results for later
./zimbra-autodiscover-validator.sh

# Fast deployment using cached results  
./zimbra-autodiscover-validator.sh --cache-only --deploy cloudflare

# Force refresh cache
./zimbra-autodiscover-validator.sh --cache-refresh
```

---

## DNS Provider Plugin System

### Plugin Architecture

Inspired by [acme.sh](https://github.com/acmesh-official/acme.sh), each provider is a self-contained script in `dnsapi/dns_providername.sh`.

```
dnsapi/
├── dns_template.sh          # Template for new providers
├── dns_cloudflare.sh        # Cloudflare API integration  
├── dns_aws.sh              # AWS Route53 integration
└── dns_yourdnshost.sh      # Your custom provider
```

### Required Provider Interface

Every provider must implement these functions:

```bash
# Provider metadata
PROVIDER_NAME="Human Readable Name"
PROVIDER_DESCRIPTION="Brief description of provider"

# Check if provider credentials are configured
dns_providername_detect() {
    # Return 0 if API credentials found, 1 otherwise
    [ -n "$PROVIDER_API_KEY" ]
}

# Add a DNS record
dns_providername_add() {
    local domain="$1"      # "company.com"
    local record_type="$2" # "SRV", "CNAME", "TXT"
    local name="$3"        # "_imaps._tcp.company.com"
    local value="$4"       # "10 0 993 mail.company.com."
    local ttl="$5"         # "300"
    
    # Provider-specific API calls here
    # Return 0 on success, 1 on failure
}

# Validate provider configuration
dns_providername_validate() {
    # Test API connectivity
    # Return 0 if working, 1 if broken
}

# Show provider help/setup instructions  
dns_providername_help() {
    cat << EOF
Setup instructions for Your DNS Provider:

1. Get API key from provider dashboard
2. Set environment variable: export PROVIDER_API_KEY="your-key"  
3. Run: ./zimbra-autodiscover-validator.sh --deploy providername

Documentation: https://provider.com/api-docs
EOF
}
```

### Example: Cloudflare Provider

```bash
dns_cloudflare_add() {
    local domain="$1"
    local record_type="$2" 
    local name="$3"
    local value="$4"
    local ttl="$5"
    
    # Get zone ID from Cloudflare API
    local zone_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$domain" \
        -H "Authorization: Bearer $CF_Token" \
        | jq -r '.result[0].id')
    
    # Create DNS record
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records" \
        -H "Authorization: Bearer $CF_Token" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$record_type\",\"name\":\"$name\",\"content\":\"$value\",\"ttl\":$ttl}"
}
```

### Creating New Providers

1. **Copy template**: `cp dnsapi/dns_template.sh dnsapi/dns_newprovider.sh`
2. **Update metadata**: Set `PROVIDER_NAME` and `PROVIDER_DESCRIPTION`
3. **Implement functions**: Focus on `dns_newprovider_add()` first
4. **Test provider**: `./zimbra-autodiscover-validator.sh --deploy newprovider`

---

## Testing Framework

### Test Result States

| State | Meaning | Action Required |
|-------|---------|-----------------|
| **PASS** | DNS record exists and is correct | None - working properly |
| **FAIL** | DNS record missing or incorrect | Add/fix DNS record |
| **INVESTIGATE** | Record exists but may need verification | Manual review needed |

### Adding New Tests

```bash
# 1. Create test function
test_new_feature() {
    local domain="$1"
    local test_name="$2"
    
    # Your test logic here
    local result=$(some_test_command)
    
    if [ condition_met ]; then
        add_test_result "$test_name" "PASS" "$result"
    else
        add_test_result "$test_name" "FAIL" "Expected X, got Y"
    fi
}

# 2. Call from main validation loop
if [ "$CACHE_LOADED" != true ] && [ "$CACHE_ONLY" != true ]; then
    # ... existing tests ...
    
    echo -e "\n${BLUE}8. New Feature Testing:${NC}"
    test_new_feature "$DOMAIN" "New Feature Test"
fi
```

### Test Organization

Tests are grouped by category:
1. **DNS SRV Records** - Core email service discovery
2. **DNS TXT Records** - Service path information  
3. **DNS CNAME Records** - Service endpoint aliases
4. **Service Availability** - HTTP/HTTPS endpoint testing
5. **Well-known URIs** - RFC-compliant discovery endpoints
6. **DAV Service Discovery** - WebDAV service testing
7. **Authenticated Validation** - Optional password-based testing

---

## Adding New Features

### Example: Adding DKIM Validation

Let's walk through adding DKIM (email authentication) validation:

#### 1. Add Test Function

```bash
test_dkim_record() {
    local domain="$1"
    local selector="$2"    # DKIM selector (usually "default")
    local test_name="$3"
    
    show_progress "Testing DKIM record: $selector._domainkey.$domain"
    
    local dkim_record=$(safe_dig TXT "$selector._domainkey.$domain")
    
    if [[ "$dkim_record" =~ "v=DKIM1" ]]; then
        add_test_result "$test_name" "PASS" "$dkim_record"
    elif [ -n "$dkim_record" ]; then
        add_test_result "$test_name" "INVESTIGATE" "TXT record exists but not valid DKIM"
    else
        add_test_result "$test_name" "FAIL" "No DKIM record found"
    fi
}
```

#### 2. Add to Main Testing Loop

```bash
echo -e "\n${BLUE}8. Email Authentication:${NC}"
echo "DKIM record:"
test_dkim_record "$DOMAIN" "default" "DKIM Authentication"
```

#### 3. Update BIND Zone Generation

```bash
# In generate_bind_zone() function
cat >> "$output" << EOF

; Email Authentication  
default._domainkey      IN  TXT "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb..."
EOF
```

#### 4. Update Provider Plugins

```bash
# In each dns_provider_add() function, handle TXT records:
case $record_type in
    "TXT")
        if [[ "$name" =~ "_domainkey" ]]; then
            # DKIM-specific handling
            provider_api_call_for_dkim "$name" "$value"
        else
            # Standard TXT record
            provider_api_call_for_txt "$name" "$value"  
        fi
        ;;
esac
```

---

## Troubleshooting Guide

### Common Issues for Developers

#### 1. Bash Array Issues
```bash
# PROBLEM: Unbound variable errors
echo ${#FAILED_TESTS[@]}  # ❌ Crashes if array empty

# SOLUTION: Safe array access  
[ ${#FAILED_TESTS[@]} -gt 0 ] 2>/dev/null && echo "Found ${#FAILED_TESTS[@]} failures"
```

#### 2. Background Process Array Modification
```bash
# PROBLEM: Background processes can't modify parent arrays
test_dns_srv "imaps" "$DOMAIN" "DNS SRV _imaps._tcp" &  # ❌ Won't update arrays

# SOLUTION: Sequential execution or temp files
test_dns_srv "imaps" "$DOMAIN" "DNS SRV _imaps._tcp"    # ✅ Updates arrays correctly
```

#### 3. JSON Generation Without jq
```bash
# Generate valid JSON without external dependencies
printf '%s\n' "${PASSED_TESTS[@]}" | jq -R . | jq -s . 2>/dev/null || echo '[]'
```

#### 4. Secure Variable Handling
```bash
# PROBLEM: Passwords in process list
curl -u "$EMAIL:$PASSWORD" https://...  # ❌ Visible in `ps aux`

# SOLUTION: Function-based credential handling  
get_auth_header() {
    local temp_creds="$EMAIL:$PASSWORD"
    echo -n "$temp_creds" | base64
    unset temp_creds
}
curl -H "Authorization: Basic $(get_auth_header)" https://...  # ✅ Hidden
```

### Debugging Tips

#### Enable Debug Mode
```bash
# Add to script for verbose debugging
set -x  # Show all commands
# ... debug section ...
set +x  # Disable debug
```

#### Test Individual Functions
```bash
# Source the script to access functions
source zimbra-autodiscover-validator.sh

# Test specific function
test_dns_srv "imaps" "company.com" "Test"
echo "Result: ${TEST_DETAILS["Test"]}"
```

#### DNS Testing
```bash
# Manual DNS testing
dig +short SRV _imaps._tcp.company.com
dig +short TXT _caldavs._tcp.company.com  
dig +short CNAME autodiscover.company.com
```

---

## Educational Resources

### Essential RFCs
- **[RFC 6186](https://tools.ietf.org/html/rfc6186)** - Use of SRV Records for Locating Email Services
- **[RFC 6764](https://tools.ietf.org/html/rfc6764)** - Locating Services for Calendaring and Contacts  
- **[RFC 2782](https://tools.ietf.org/html/rfc2782)** - A DNS RR for specifying the location of services (DNS SRV)

### Autodiscovery Specifications
- **Microsoft Autodiscover**: [Exchange Autodiscover](https://docs.microsoft.com/en-us/exchange/client-developer/exchange-web-services/autodiscover-for-exchange)
- **Mozilla Autoconfig**: [Thunderbird Autoconfig](https://wiki.mozilla.org/Thunderbird:Autoconfiguration)
- **CalDAV/CardDAV**: [Apple Calendar/Contacts Discovery](https://tools.ietf.org/html/rfc6764)

### DNS Concepts
- **DNS Record Types**: [Cloudflare DNS Records Guide](https://www.cloudflare.com/learning/dns/dns-records/)
- **SRV Records Explained**: [DigitalOcean SRV Guide](https://www.digitalocean.com/community/tutorials/an-introduction-to-dns-terminology-components-and-concepts)

### Bash Scripting  
- **Advanced Bash**: [Bash Guide](https://mywiki.wooledge.org/BashGuide)
- **Bash Arrays**: [Array Tutorial](https://www.thegeekstuff.com/2010/06/bash-array-tutorial/)
- **Error Handling**: [Bash Error Handling](https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html)

### Zimbra Documentation
- **Zimbra Autodiscover Setup**: [Official Zimbra Docs](https://wiki.zimbra.com/wiki/Autodiscover)
- **Zimbra Best Practices**: [Mission Critical Email Guide](https://www.missioncriticalemail.com/2025/07/22/autodiscover-records-best-practices-for-zimbra/)

### API Documentation
- **Cloudflare API**: [DNS Records API](https://developers.cloudflare.com/api/operations/dns-records-for-a-zone-create-dns-record)
- **AWS Route53 API**: [Route53 CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/route53/)

---

## Contributing Guidelines

### Code Style
- Use 4-space indentation
- Quote all variable references: `"$VARIABLE"`
- Use meaningful function and variable names
- Add comments explaining complex logic
- Follow existing error handling patterns

### Testing New Features
1. Test with various DNS configurations
2. Test failure scenarios (missing records, timeouts)
3. Test with and without authentication 
4. Verify caching works correctly
5. Test JSON and text output formats

### Documentation Requirements
- Update `INTERNALS.md` for architectural changes
- Update `README.md` for user-facing features
- Add inline comments for complex functions
- Update help text and examples

---

*This document serves as both educational material and technical reference. When in doubt, refer to the actual source code as the definitive implementation guide.*