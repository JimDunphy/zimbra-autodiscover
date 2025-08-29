# Author: Mark Stone
* https://www.missioncriticalemail.com/2025/07/22/autodiscover-records-best-practices-for-zimbra/

# Zimbra Autodiscover Validator

A comprehensive DNS configuration validator and zone generator for Zimbra email autodiscovery. This diagnostic tool validates all required DNS records for proper email client autoconfiguration, reports what's missing, and generates BIND zone file entries to fix configuration issues.

## Features

- **Complete DNS Validation**: Tests all required SRV, TXT, and CNAME records for Zimbra autodiscovery
- **Service Endpoint Testing**: Validates HTTP/HTTPS endpoints for ActiveSync, Thunderbird, CalDAV, and CardDAV
- **Graceful Error Handling**: Continues testing when records are missing - reports what needs to be configured
- **Diagnostic Reporting**: Clearly identifies missing, configured, and problematic DNS records
- **Reliable Testing**: Sequential execution ensures all test results are captured accurately
- **Security Focused**: Secure credential handling, input sanitization, safe error handling
- **Multiple Output Formats**: Human-readable reports or structured JSON output for automation
- **BIND Zone Generation**: Creates ready-to-use DNS zone file entries for missing records
- **Authenticated Testing**: Optional password-based service validation
- **Retry Logic**: Automatic retry with configurable timeouts for unreliable networks
- **Progress Tracking**: Real-time status updates with timestamps

## Requirements

- `dig` (DNS lookup utility)
- `curl` (HTTP client)
- `bash` 4.0+
- `jq` (for JSON output, optional)

## Installation

```bash
git clone git@github.com:JimDunphy/zimbra-autodiscover.git
cd zimbra-autodiscover
chmod +x zimbra-autodiscover-validator.sh
```

## Version Management

**Current Version:** 2.1.0

### Check Version
```bash
./zimbra-autodiscover-validator.sh --version
```

### Check for Updates
```bash
./zimbra-autodiscover-validator.sh --check-updates
```

### Auto-Update (Git Repository)
```bash
./zimbra-autodiscover-validator.sh --update
```

**Manual Update:**
```bash
git pull origin main
chmod +x zimbra-autodiscover-validator.sh
```

## Usage

### Basic Usage

```bash
./zimbra-autodiscover-validator.sh
```

### Command Line Options

```bash
./zimbra-autodiscover-validator.sh [OPTIONS]

Options:
  -q, --quiet         Suppress progress messages
  -j, --json          Output results in JSON format
  -c, --config FILE   Use configuration file
  -g, --generate      Generate BIND zone entries after validation
  -b, --bind-zone     Generate BIND zone entries only (no validation)
  -e, --example-config Generate example configuration file
  --cache-only        Use cached results without re-testing DNS
  --cache-refresh     Force refresh cache and re-test everything
  --deploy PROVIDER   Deploy missing records to DNS provider
  --no-auth          Skip authentication prompts
  -v, --version       Show version information
  --check-updates     Check for available updates
  --update            Update script from GitHub repository
  -h, --help          Show comprehensive help message
```

### Examples

**Interactive validation:**
```bash
./zimbra-autodiscover-validator.sh
```

**Quiet mode with JSON output:**
```bash
./zimbra-autodiscover-validator.sh --quiet --json > results.json
```

**Generate BIND zone entries:**
```bash
./zimbra-autodiscover-validator.sh --generate
```

**Use configuration file:**
```bash
./zimbra-autodiscover-validator.sh --config /path/to/config.conf
```

**Quick BIND zone generation for missing records:**
```bash
./zimbra-autodiscover-validator.sh --bind-zone
```

**Generate example configuration:**
```bash
./zimbra-autodiscover-validator.sh --example-config > myconfig.conf
```

## Configuration File

Create a configuration file to automate input:

```bash
# Example configuration
EMAIL="user@example.com"
MAIL_SERVER="mail.example.com"
DOMAIN="example.com"

# Optional: Override default timeouts
DIG_TIMEOUT=15
CURL_TIMEOUT=45
MAX_RETRIES=5
```

Generate an example configuration:
```bash
./zimbra-autodiscover-validator.sh --example-config > zimbra-config.conf
```

## How It Works

This tool is designed as a **diagnostic validator** that helps administrators understand their current Zimbra autodiscover DNS configuration:

### ✅ **Non-Destructive Testing**
- Never modifies DNS records or server configuration
- Only performs read-only DNS queries and HTTP HEAD requests
- Safe to run on production systems

### ✅ **Graceful Failure Handling**
- Continues testing even when DNS records don't exist
- Reports each missing component clearly
- Never crashes on network timeouts or missing records

### ✅ **Actionable Results**
- **PASS**: DNS record exists and is properly configured
- **FAIL**: DNS record is missing or incorrect - needs configuration
- **INVESTIGATE**: Record exists but may need manual verification

### ✅ **Implementation Guidance**
- Generates exact BIND zone entries for missing records
- Provides specific commands to test each DNS record type
- Includes port numbers, priorities, and proper syntax

### ✅ **Intelligent Caching System**
- **1-hour cache** of validation results stored in `~/.zimbra-autodiscover/cache/{domain}.json`
- **Fast re-runs** - Skip DNS queries when using cached results
- **Automatic deployment** - Use `--cache-only --deploy` for instant DNS provider updates
- **Cache refresh** - Use `--cache-refresh` to force re-validation

## Authentication Testing (Optional)

The tool supports **optional** email password testing for comprehensive service validation:

### 🔐 **What Email Password Testing Does**
When you provide your email password, the tool performs **authenticated validation** of:

1. **ActiveSync Autodiscover Service**
   - Tests actual XML response format with real credentials
   - Verifies the autodiscover endpoint returns valid configuration
   - Ensures mobile devices can auto-configure correctly

2. **CalDAV Service Response**
   - Tests WebDAV PROPFIND requests with authentication
   - Verifies calendar sync endpoints work end-to-end
   - Confirms proper DAV XML responses

3. **CardDAV Service Response**
   - Tests contact sync endpoints with real credentials
   - Verifies address book autodiscovery works correctly
   - Ensures proper WebDAV authentication flow

### 🚫 **When to Skip Authentication Testing**
You can safely skip password testing in these scenarios:

- **Infrastructure Validation**: Only need to verify DNS records exist
- **Security Policies**: Don't want to transmit passwords over network
- **Automation/CI**: Running in scripts where passwords aren't available
- **Initial Setup**: DNS records don't exist yet, services won't work anyway
- **Quick Check**: Just want to see what DNS records are missing

### 🎯 **How to Skip Authentication**
```bash
# Option 1: Command line flag
./zimbra-autodiscover-validator.sh --no-auth

# Option 2: Config file setting
SKIP_AUTH_PROMPT=true

# Option 3: Just press Enter when prompted
Enter password for user@domain.com (press Enter to skip): [ENTER]
```

### ✅ **DNS-Only vs Full Testing Comparison**

| Test Type | DNS Only | With Password |
|-----------|----------|---------------|
| SRV/TXT/CNAME Records | ✅ | ✅ |
| HTTP Endpoint Availability | ✅ | ✅ |
| ActiveSync XML Response | ❌ | ✅ |
| CalDAV/CardDAV Authentication | ❌ | ✅ |
| End-to-End Service Validation | ❌ | ✅ |
| **Use Case** | Infrastructure Setup | Service Verification |

**Recommendation**: Use DNS-only testing (`--no-auth`) for initial setup and automation. Use authenticated testing only when you need to verify end-user experience.

## DNS Records Tested

### SRV Records
- `_imaps._tcp.domain.com` - IMAP over SSL
- `_submission._tcp.domain.com` - SMTP submission
- `_autodiscover._tcp.domain.com` - Exchange autodiscover
- `_caldavs._tcp.domain.com` - CalDAV over SSL
- `_carddavs._tcp.domain.com` - CardDAV over SSL

### TXT Records
- `_caldavs._tcp.domain.com` - CalDAV path information
- `_carddavs._tcp.domain.com` - CardDAV path information

### CNAME Records
- `autodiscover.domain.com` - Autodiscover endpoint

### HTTP/HTTPS Endpoints
- `https://autodiscover.domain.com/autodiscover/autodiscover.xml`
- `https://autoconfig.domain.com/mail/config-v1.1.xml`
- `https://mailserver/.well-known/carddav`
- `https://mailserver/.well-known/caldav`
- `https://mailserver/service/dav/home/`

## Sample Output

### Standard Output
```
[10:15:30] Testing SRV record: imaps
10 0 993 mail.example.com.
✓ DNS SRV _imaps._tcp

[10:15:31] Testing HTTP endpoint: https://autodiscover.example.com/autodiscover/autodiscover.xml
HTTP/1.1 200 OK
✓ ActiveSync Autodiscover Service

=============================================
ZIMBRA AUTODISCOVER DNS VALIDATION REPORT
=============================================

✓ DNS CONFIGURATION VALIDATED (8):
 ✓ DNS SRV _imaps._tcp
 ✓ DNS SRV _submission._tcp
 ✓ ActiveSync Autodiscover Service
 ...

DNS CONFIGURATION SUMMARY:
Total autodiscover components tested: 12
Properly configured: 8
Need review: 2
Missing configuration: 2

✓ AUTODISCOVER DNS CONFIGURATION COMPLETE
```

### JSON Output
```json
{
  "timestamp": "2025-01-15T10:15:45-05:00",
  "domain": "example.com",
  "email": "user@example.com",
  "mail_server": "mail.example.com",
  "summary": {
    "total_tests": 12,
    "passed": 8,
    "failed": 2,
    "needs_investigation": 2
  },
  "results": {
    "passed": ["DNS SRV _imaps._tcp", "DNS SRV _submission._tcp"],
    "failed": ["DNS TXT _caldavs._tcp", "DNS TXT _carddavs._tcp"],
    "needs_investigation": ["Thunderbird Autoconfig Service"]
  },
  "status": "mostly_configured"
}
```

### BIND Zone Generation
```bind
; Zimbra Autodiscover DNS Records for example.com
; Generated on 2025-01-15 10:15:45

; SRV Records
_imaps._tcp             IN  SRV 10 0 993  mail.example.com.
_submission._tcp        IN  SRV 10 0 587  mail.example.com.
_autodiscover._tcp      IN  SRV 10 0 443  mail.example.com.
_caldavs._tcp          IN  SRV 10 0 443  mail.example.com.
_carddavs._tcp         IN  SRV 10 0 443  mail.example.com.

; TXT Records for DAV paths
_caldavs._tcp          IN  TXT "path=/service/dav/home/"
_carddavs._tcp         IN  TXT "path=/service/dav/home/"

; CNAME Records
autodiscover           IN  CNAME mail.example.com.
autoconfig             IN  CNAME mail.example.com.
```

## Security Features

- **Secure Credential Handling**: Passwords never stored in environment variables or process arguments
- **Input Sanitization**: All user inputs sanitized to prevent command injection
- **SSL/TLS Validation**: Forces TLS 1.2+, validates certificates, checks OCSP status
- **Timeout Protection**: Configurable timeouts prevent hanging operations
- **Error Isolation**: Robust error handling with graceful degradation

## Troubleshooting

### Common Issues

**Missing dependencies:**
```bash
# Ubuntu/Debian
sudo apt-get install dnsutils curl jq

# CentOS/RHEL
sudo yum install bind-utils curl jq

# macOS
brew install bind jq
```

**DNS timeout errors:**
- Increase `DIG_TIMEOUT` in configuration
- Check firewall settings  
- Verify DNS server accessibility
- Script will continue testing other records if some fail

**SSL certificate errors:**
- Script uses relaxed SSL checking for testing purposes
- Ensure mail server has valid SSL certificate for production
- Check certificate chain completeness

**Script stops with "unbound variable" error:**
- This was fixed in v2.0.1 - update to latest version
- Older bash versions had compatibility issues with array handling

**Permission denied:**
```bash
chmod +x zimbra-autodiscover-validator.sh
```

**Script appears to hang:**
- Default timeouts are 10s for DNS, 30s for HTTP
- Use `timeout 60 ./zimbra-autodiscover-validator.sh` to limit total runtime
- Check network connectivity to test domains

## Integration

### CI/CD Pipeline
```yaml
- name: Validate Zimbra DNS
  run: |
    ./zimbra-autodiscover-validator.sh --quiet --json > dns-results.json
    if [ $(jq -r '.summary.failed' dns-results.json) -gt 0 ]; then
      echo "DNS validation failed"
      exit 1
    fi
```

### Monitoring Script
```bash
#!/bin/bash
# Monitor autodiscover configuration
./zimbra-autodiscover-validator.sh --config prod.conf --json | \
  jq -r 'if .summary.failed > 0 then "CRITICAL: DNS issues detected" else "OK: All DNS records valid" end'
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Testing

Run the test suite:
```bash
./tests/run-tests.sh
```

## License

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

## References

- [Zimbra Autodiscover Best Practices](https://www.missioncriticalemail.com/2025/07/22/autodiscover-records-best-practices-for-zimbra/)
- [RFC 6186 - Use of SRV Records for Locating Email Services](https://tools.ietf.org/html/rfc6186)
- [RFC 6764 - Locating Services for Calendaring and Contacts](https://tools.ietf.org/html/rfc6764)

## Changelog

### v2.1.0 (Latest)
- **Added**: Version management system with `--version`, `--check-updates`, and `--update` commands
- **Added**: Comprehensive INTERNALS.md documentation for developers
- **Added**: GitHub repository integration for automatic updates
- **Added**: Educational content about email autodiscovery for junior developers
- **Improved**: Repository setup and contribution guidelines

### v2.0.1
- **Fixed**: Script no longer crashes on missing DNS records - continues testing
- **Fixed**: Unbound variable errors with `NEEDS_INVESTIGATION` array
- **Fixed**: Bash compatibility issues with older versions
- **Improved**: Graceful error handling for network timeouts
- **Improved**: Better diagnostic reporting for missing vs configured records
- **Added**: `--bind-zone` option for quick zone generation without validation

### v2.0.0
- Added parallel DNS query execution
- Implemented secure credential handling
- Added BIND zone generation
- Enhanced SSL/TLS validation
- Added JSON output format
- Improved error handling and retry logic

### v1.0.0
- Initial release
- Basic DNS record validation
- HTTP endpoint testing
