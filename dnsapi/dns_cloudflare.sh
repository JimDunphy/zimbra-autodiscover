#!/usr/bin/env bash

# DNS Provider: Cloudflare
# Documentation: https://developers.cloudflare.com/api/
# Required Environment Variables:
#   CF_Token - Cloudflare API Token (recommended) OR
#   CF_Key + CF_Email - Global API Key + Account Email

PROVIDER_NAME="Cloudflare"
PROVIDER_DESCRIPTION="Cloudflare DNS API"
CF_API="https://api.cloudflare.com/client/v4"

# Check if provider is configured and available
dns_cloudflare_detect() {
    if [ -n "$CF_Token" ]; then
        echo "Cloudflare provider available (API Token)"
        return 0
    elif [ -n "$CF_Key" ] && [ -n "$CF_Email" ]; then
        echo "Cloudflare provider available (Global API Key)"
        return 0
    else
        echo "CF_Token or (CF_Key + CF_Email) not set - provider unavailable"
        return 1
    fi
}

# Get zone ID for domain
_get_zone_id() {
    local domain="$1"
    local response
    
    if [ -n "$CF_Token" ]; then
        response=$(curl -s -H "Authorization: Bearer $CF_Token" \
                     -H "Content-Type: application/json" \
                     "$CF_API/zones?name=$domain")
    else
        response=$(curl -s -H "X-Auth-Key: $CF_Key" \
                     -H "X-Auth-Email: $CF_Email" \
                     -H "Content-Type: application/json" \
                     "$CF_API/zones?name=$domain")
    fi
    
    # Extract zone ID using basic text processing
    echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4
}

# Add a DNS record
dns_cloudflare_add() {
    local domain="$1"
    local record_type="$2" 
    local name="$3"
    local value="$4"
    local ttl="${5:-300}"
    
    echo "Adding $record_type record to Cloudflare: $name"
    
    # Get zone ID
    local zone_id=$(_get_zone_id "$domain")
    if [ -z "$zone_id" ]; then
        echo "Error: Could not find zone ID for $domain"
        return 1
    fi
    
    local data=""
    case "$record_type" in
        "SRV")
            # Parse SRV: "10 0 993 mail.example.com"
            local priority=$(echo "$value" | cut -d' ' -f1)
            local weight=$(echo "$value" | cut -d' ' -f2) 
            local port=$(echo "$value" | cut -d' ' -f3)
            local target=$(echo "$value" | cut -d' ' -f4)
            
            data="{\"type\":\"SRV\",\"name\":\"$name\",\"data\":{\"priority\":$priority,\"weight\":$weight,\"port\":$port,\"target\":\"$target\"},\"ttl\":$ttl}"
            ;;
        "CNAME")
            data="{\"type\":\"CNAME\",\"name\":\"$name\",\"content\":\"$value\",\"ttl\":$ttl}"
            ;;
        "TXT") 
            data="{\"type\":\"TXT\",\"name\":\"$name\",\"content\":\"$value\",\"ttl\":$ttl}"
            ;;
        *)
            echo "Error: Unsupported record type: $record_type"
            return 1
            ;;
    esac
    
    # Make API call
    local response
    if [ -n "$CF_Token" ]; then
        response=$(curl -s -X POST \
                     -H "Authorization: Bearer $CF_Token" \
                     -H "Content-Type: application/json" \
                     -d "$data" \
                     "$CF_API/zones/$zone_id/dns_records")
    else
        response=$(curl -s -X POST \
                     -H "X-Auth-Key: $CF_Key" \
                     -H "X-Auth-Email: $CF_Email" \
                     -H "Content-Type: application/json" \
                     -d "$data" \
                     "$CF_API/zones/$zone_id/dns_records")
    fi
    
    # Check success
    if echo "$response" | grep -q '"success":true'; then
        echo "Successfully added $record_type record: $name"
        return 0
    else
        echo "Error adding record: $response"
        return 1
    fi
}

# Validate provider configuration
dns_cloudflare_validate() {
    if [ -n "$CF_Token" ]; then
        echo "Testing Cloudflare API Token..."
        local response=$(curl -s -H "Authorization: Bearer $CF_Token" \
                           -H "Content-Type: application/json" \
                           "$CF_API/user/tokens/verify")
        
        if echo "$response" | grep -q '"success":true'; then
            echo "✓ Cloudflare API Token valid"
            return 0
        else
            echo "✗ Cloudflare API Token invalid or expired"
            return 1
        fi
    elif [ -n "$CF_Key" ] && [ -n "$CF_Email" ]; then
        echo "Testing Cloudflare Global API Key..."
        local response=$(curl -s -H "X-Auth-Key: $CF_Key" \
                           -H "X-Auth-Email: $CF_Email" \
                           -H "Content-Type: application/json" \
                           "$CF_API/user")
        
        if echo "$response" | grep -q '"success":true'; then
            echo "✓ Cloudflare Global API Key valid"
            return 0
        else
            echo "✗ Cloudflare Global API Key invalid"
            return 1
        fi
    else
        echo "Error: CF_Token or (CF_Key + CF_Email) required"
        return 1
    fi
}

# Show provider-specific help
dns_cloudflare_help() {
    cat << EOF
Cloudflare DNS Provider Configuration:

Option 1 - API Token (Recommended):
  export CF_Token="your-api-token"

Option 2 - Global API Key:
  export CF_Key="your-global-api-key"
  export CF_Email="your-cloudflare-email"

Setup Instructions:
1. Log in to Cloudflare Dashboard
2. Go to My Profile -> API Tokens
3. Create Token with Zone:Edit permissions for your domain
4. Set CF_Token environment variable

Example Usage:
  export CF_Token="abc123..."
  ./zimbra-autodiscover-validator.sh --deploy cloudflare

Supported Record Types: SRV, CNAME, TXT
Rate Limits: 1200 requests per 5 minutes
EOF
}