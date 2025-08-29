# DNS Provider Plugins for Zimbra Autodiscover Validator

This system uses a modular plugin architecture similar to [acme.sh](https://github.com/acmesh-official/acme.sh) to support automatic DNS record deployment across multiple DNS providers.

## Available Providers

- **Cloudflare** - Full API support with API Token or Global API Key
- **AWS Route53** - Full API support via AWS CLI
- **Template** - Example template for creating new providers

## Quick Start

### 1. Validate and Deploy to Cloudflare
```bash
# Set your Cloudflare API token
export CF_Token="your-cloudflare-api-token"

# Validate DNS and deploy missing records
./zimbra-autodiscover-validator.sh --deploy cloudflare
```

### 2. Deploy to AWS Route53
```bash  
# Configure AWS CLI
aws configure

# Deploy missing records
./zimbra-autodiscover-validator.sh --deploy aws
```

### 3. Use Cached Results for Faster Deployment
```bash
# First run validates and caches results
./zimbra-autodiscover-validator.sh

# Later deployments use cache (faster)
./zimbra-autodiscover-validator.sh --cache-only --deploy cloudflare
```

## DNS Provider API Interface

Each provider plugin implements these functions:

### Required Functions
```bash
# Check if provider is configured
dns_PROVIDER_detect()

# Add a DNS record  
dns_PROVIDER_add(domain, record_type, name, value, ttl)

# Validate provider configuration
dns_PROVIDER_validate()

# Show provider help
dns_PROVIDER_help()
```

### Required Variables
```bash
PROVIDER_NAME="Human Readable Name"
PROVIDER_DESCRIPTION="Brief description"
```

## Creating New Providers

1. **Copy Template:**
   ```bash
   cp dnsapi/dns_template.sh dnsapi/dns_newprovider.sh
   ```

2. **Implement Functions:**
   - Update `PROVIDER_NAME` and `PROVIDER_DESCRIPTION`
   - Implement `dns_newprovider_detect()`
   - Implement `dns_newprovider_add()` for SRV, CNAME, TXT records
   - Update `dns_newprovider_validate()` and `dns_newprovider_help()`

3. **Test Your Provider:**
   ```bash
   ./zimbra-autodiscover-validator.sh --list-providers
   ./zimbra-autodiscover-validator.sh --deploy newprovider
   ```

## Supported Record Types

All providers must support these Zimbra autodiscover record types:

### SRV Records
```
_imaps._tcp.domain.com.        IN SRV 10 0 993 mail.domain.com.
_submission._tcp.domain.com.   IN SRV 10 0 587 mail.domain.com.
_autodiscover._tcp.domain.com. IN SRV 10 0 443 mail.domain.com.
_caldavs._tcp.domain.com.      IN SRV 10 0 443 mail.domain.com.
_carddavs._tcp.domain.com.     IN SRV 10 0 443 mail.domain.com.
```

### CNAME Records
```
autodiscover.domain.com.       IN CNAME mail.domain.com.
```

### TXT Records
```
_caldavs._tcp.domain.com.      IN TXT "path=/service/dav/home/"
_carddavs._tcp.domain.com.     IN TXT "path=/service/dav/home/"
```

## Provider-Specific Setup

### Cloudflare Setup
1. Get API Token from [Cloudflare Dashboard](https://dash.cloudflare.com/profile/api-tokens)
2. Create token with `Zone:Edit` permissions
3. Set environment: `export CF_Token="your-token"`

### AWS Route53 Setup  
1. Install AWS CLI: `pip install awscli`
2. Configure credentials: `aws configure`
3. Ensure IAM permissions: `route53:ListHostedZones`, `route53:ChangeResourceRecordSets`

## Architecture Benefits

### ✅ **Extensible**
- Easy to add new DNS providers
- Consistent interface across all providers
- Plugin system isolates provider-specific logic

### ✅ **Reliable** 
- Provider detection prevents deployment failures
- Validation ensures credentials work before deployment
- Clear error messages for troubleshooting

### ✅ **Cached**
- Results cached for 1 hour by default
- `--cache-only` for fast repeated deployments  
- `--cache-refresh` to force re-testing

### ✅ **Secure**
- No credentials stored in scripts
- Environment variable based configuration
- Provider-specific validation

## Contributing New Providers

Popular DNS providers to implement:
- Google Cloud DNS
- DigitalOcean DNS
- Namecheap
- GoDaddy
- DNSimple

Submit pull requests with new providers following the template pattern!