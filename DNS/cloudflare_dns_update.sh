#!/usr/bin/env bash

# Credit to https://gist.github.com/Tras2/cba88201b17d765ec065ccbedfb16d9a

# Function to log messages
log() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %T")
    echo "[$timestamp] $1"
}

# Check if required commands are available
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        log "Error: 'jq' command not found. Please install it."
        exit 1
    fi
}

# Check for required dependencies
check_dependencies

# Get the directory of the script
script_dir=$(dirname "$(readlink -f "$0")")

# Define the path to the secrets file
secrets_file="$script_dir/secrets.txt"

# Check if the secrets file exists
if [[ ! -f "$secrets_file" ]]; then
    log "Error: Secrets file not found: $secrets_file"
    exit 1
fi

# Source the secrets file
source "$secrets_file"

set -e

api_token=$API_TOKEN # API Token with DNS edit permission for the zone
email=$ACCOUNT_EMAIL # Cloudflare Account email address
zone_name=$ZONE_NAME # Cloduflare zone to update DOMAIN.TLD
dns_record=$DNS_RECORD # full record to update (must exist) HOST.DOMAIN.TLD

user_id=$(curl -s \
        -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type:application/json" \
        | jq -r '{"result"}[] | .id')

zone_id=$(curl -s \
        -X GET "https://api.cloudflare.com/client/v4/zones?name=$zone_name&status=active" \
        -H "Content-Type: application/json" \
        -H "X-Auth-Email: $email" \
        -H "Authorization: Bearer $api_token" \
        | jq -r '{"result"}[] | .[0] | .id')

record_data=$(curl -s \
        -X GET "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=A&name=$dns_record"  \
        -H "Content-Type: application/json" \
        -H "X-Auth-Email: $email" \
        -H "Authorization: Bearer $api_token")

record_id=$(jq -r '{"result"}[] | .[0] | .id' <<< $record_data)
cf_ip=$(jq -r '{"result"}[] | .[0] | .content' <<< $record_data)
ext_ip=$(curl -s -X GET -4 https://ifconfig.co)

if [[ $cf_ip != $ext_ip ]]; then
        result=$(curl -s \
                -X PUT "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id" \
                -H "Content-Type: application/json" \
                -H "X-Auth-Email: $email" \
                -H "Authorization: Bearer $api_token" \
                --data "{\"type\":\"A\",\"name\":\"$dns_record\",\"content\":\"$ext_ip\",\"ttl\":1,\"proxied\":false}" \
                | jq -r '.success')
        if [[ $result == "true" ]]; then
                log "$dns_record updated to: $ext_ip"
                exit 0
        else
                log "$dns_record update failed"
                exit 1
        fi
else
        log "$dns_record already up to date"
        exit 0
fi
