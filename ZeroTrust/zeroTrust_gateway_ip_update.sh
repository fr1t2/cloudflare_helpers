#!/usr/bin/env bash

# Function to log messages
log() {
    local timestamp
    timestamp=$(date +"%Y-%m-%d %T")
    echo "[$timestamp] $1"
}

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

# Function to check for updates from GitHub repository
check_for_updates() {
    # Define the branch to check for updates
    branch="main"

    # Log message indicating the start of update check
    log "Checking for updates..."

    # Navigate to the GitHub repository directory
    cd "$(dirname "${BASH_SOURCE[0]}")"

    # Fetch the latest changes from the remote repository
    git fetch origin "$branch"

    # Check if there are any changes
    if git diff --quiet HEAD "origin/$branch"; then
        log "No updates available."
    else
        log "Updates found. Pulling changes..."
        # Pull the latest changes from the remote repository
        git pull origin "$branch"
    fi
}


if [[ "$AUTO_UPDATE" == "true" ]]; then
    # Run the function to check for updates
    check_for_updates
fi




# Check if required commands are available
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        log "Error: 'jq' command not found. Please install it."
        exit 1
    fi
}

# Check for required dependencies
check_dependencies

# API Token and Account ID
api_token=$API_TOKEN # API token with Account|Zero Trust|Edit permissions
account_id=$ACCOUNT_ID # from the main cloudflare account (URL or any domain dashboard)

# DNS Location Name and IP Check Address
dns_location_name=$DNS_GATEWAY_LOCATION_NAME # https://one.dash.cloudflare.com/$account_id/gateway/locations <-- must match name given here
ip_check_addr=ifconfig.co # service to return IPv4 address in format XXX.XXX.XXX.XXX


set -e

# Function to make HTTP GET request
http_get() {
    local url="$1"
    curl -s -X GET "$url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json"
}

# Function to make HTTP PUT request
http_put() {
    local url="$1"
    local data="$2"
    
    # Make the PUT request and capture both stdout and stderr
    response=$(curl -s -w "\n%{http_code}" -X PUT "$url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        -d "$data" 2>&1)

    # Extract the JSON response from stdout
    echo "$response" | sed -n '1,/^$/p'
}

# Verify the user API key
verify_key() {
    local api_token_check=$(http_get "https://api.cloudflare.com/client/v4/user/tokens/verify")
    
    # Check if the response is empty
    if [[ -z "$api_token_check" ]]; then
        log "Error: Empty response received while verifying API key."
        exit 1
    fi
    
    # Check if the response contains the 'result' field
    if ! jq -e '.result' <<< "$api_token_check" >/dev/null; then
        log "Error: Missing 'result' field in API key verification response."
        exit 1
    fi
    
    # Check if the response contains the 'status' field within 'result'
    if ! jq -e '.result.status' <<< "$api_token_check" >/dev/null; then
        log "Error: Missing 'status' field in API key verification response."
        exit 1
    fi
    
    # Check if the response contains the 'id' field within 'result'
    if ! jq -e '.result.id' <<< "$api_token_check" >/dev/null; then
        log "Error: Missing 'id' field in API key verification response."
        exit 1
    fi
    
    echo "$api_token_check"
}

# Check API key function and connection
check_api_key() {
    local api_token_check=$(verify_key)
    if [[ -z $api_token_check ]]; then
        log "Error: Invalid API key or other errors."
        exit 1
    fi
    local status=$(echo "$api_token_check" | jq -r '.result.status')
    local id=$(echo "$api_token_check" | jq -r '.result.id')
    log "API key status: $status"
    log "API key ID: $id"
}

# Retrieve location ID based on given dns_location_name
get_location_data() {
    local location_data=$(http_get "https://api.cloudflare.com/client/v4/accounts/$account_id/gateway/locations")
    if [[ -z $location_data ]]; then
        log "Error: Unable to retrieve location data."
        exit 1
    fi
    echo "$location_data"
}

get_this_ip() {
    local ip=$(http_get "https://$ip_check_addr")
    
    # Check if the returned IP address is empty
    if [[ -z "$ip" ]]; then
        log "Error: Unable to retrieve local IP address."
        exit 1
    fi
    
    # Use regex to validate the IP address format
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "Error: Invalid IP address format: $ip"
        exit 1
    fi
    
    # Extract the first IPv4 address if there are multiple addresses
    ip=$(echo "$ip" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    
    echo "$ip"
}

put_network_addr() {
    # add new IP Address to Zero Trust Gateway Location
    local account_id="$1"
    local location="$2"
    local ipv4="$3"
    # https://developers.cloudflare.com/api/operations/zero-trust-gateway-locations-update-zero-trust-gateway-location
    http_put "https://api.cloudflare.com/client/v4/accounts/$account_id/gateway/locations/$location" "{ \"client_default\": false, \"ecs_support\": false, \"name\": \"$dns_location_name\", \"networks\": [{ \"network\": \"$ipv4/32\" }]}"
}

put_default_network_addr() {
    # add new IP Address to Zero Trust Gateway for DEFAULT Location 
    local account_id="$1"
    local location="$2"
    local ipv4="$3"
    # https://developers.cloudflare.com/api/operations/zero-trust-gateway-locations-update-zero-trust-gateway-location
    http_put "https://api.cloudflare.com/client/v4/accounts/$account_id/gateway/locations/$location" "{ \"client_default\": true, \"ecs_support\": false, \"name\": \"$dns_location_name\", \"networks\": [{ \"network\": \"$ipv4/32\" }]}"
}

# Check API key and get location ID data
check_api_key
location_id_data=$(get_location_data)

# Get the local IPv4 address
local_ipv4=$(get_this_ip)

# Extract network information for the DNS location
network=$(echo "$location_id_data" | jq -r --arg dns_location_name "$dns_location_name" '
    .result[]
    | select(.name == $dns_location_name)
    | if has("networks") then .networks[].network else empty end
')

# Get the location ID
location_id=$(echo "$location_id_data" | jq -r ".result[] | select(.name == \"$dns_location_name\") | .id")

# Get the default status of record
default_record=$(echo "$location_id_data" | jq -r ".result[] | select(.name == \"$dns_location_name\") | .client_default")

if [[ -n $network ]]; then
    network=$(echo "$network" | sed 's:/[0-9]\+$::')  # Remove subnet suffix
    log "Current network for $dns_location_name: $network"
    if [[ "$network" == "$local_ipv4" ]]; then
        log "Everything is up to date. Have a great day!"
        exit 0
    else
        log "Local Network address: $local_ipv4"
        log "New address detected..."
        if [[ "$default_record" == "true" ]]; then
            response=$(put_default_network_addr "$account_id" "$location_id" "$local_ipv4")
        else
            response=$(put_network_addr "$account_id" "$location_id" "$local_ipv4")
        fi

        if [[ "$(echo "$response" | jq -r '.success')" == "true" ]]; then
            log "Network address added successfully! DNS is protected."
        else
            log "Failed to update network address. Exiting..."
            exit 1
        fi
    fi
else
    log "Network for $dns_location_name does not exist."

    if [[ "$default_record" == "true" ]]; then
        response=$(put_default_network_addr "$account_id" "$location_id" "$local_ipv4")
    else
        response=$(put_network_addr "$account_id" "$location_id" "$local_ipv4")
    fi

    success=$(echo "$response" | jq -r '.success')

    if [[ "$success" == "true" ]]; then
        log "Network address updated successfully! DNS is protected."
        exit 0
    else
        # Extract the error code and message from the response
        error_code=$(echo "$response" | jq -r '.errors[0].code')
        error_message=$(echo "$response" | jq -r '.errors[0].message')
        log "Failed to update network address. Error code: $error_code. Error message: $error_message"
        exit 1
    fi
fi


















set -e

# Function to make HTTP GET request
http_get() {
    local url="$1"
    curl -s -X GET "$url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json"
}

# Function to make HTTP PUT request
http_put() {
    local url="$1"
    local data="$2"
    
    # Make the PUT request and capture both stdout and stderr
    response=$(curl -s -w "\n%{http_code}" -X PUT "$url" \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        -d "$data" 2>&1)

    # Extract the JSON response from stdout
    echo "$response" | sed -n '1,/^$/p'
}

# Verify the user API key
verify_key() {
    local api_token_check=$(http_get "https://api.cloudflare.com/client/v4/user/tokens/verify")
    
    # Check if the response is empty
    if [[ -z "$api_token_check" ]]; then
        echo "Error: Empty response received while verifying API key."
        exit 1
    fi
    
    # Check if the response contains the 'result' field
    if ! jq -e '.result' <<< "$api_token_check" >/dev/null; then
        echo "Error: Missing 'result' field in API key verification response."
        exit 1
    fi
    
    # Check if the response contains the 'status' field within 'result'
    if ! jq -e '.result.status' <<< "$api_token_check" >/dev/null; then
        echo "Error: Missing 'status' field in API key verification response."
        exit 1
    fi
    
    # Check if the response contains the 'id' field within 'result'
    if ! jq -e '.result.id' <<< "$api_token_check" >/dev/null; then
        echo "Error: Missing 'id' field in API key verification response."
        exit 1
    fi
    
    echo "$api_token_check"
}

# Check API key function and connection
check_api_key() {
    local api_token_check=$(verify_key)
    if [[ -z $api_token_check ]]; then
        echo "Error: Invalid API key or other errors."
        exit 1
    fi
    local status=$(echo "$api_token_check" | jq -r '.result.status')
    local id=$(echo "$api_token_check" | jq -r '.result.id')
    echo "API key status: $status"
    echo "API key ID: $id"
}

# Retrieve location ID based on given dns_location_name
get_location_data() {
    local location_data=$(http_get "https://api.cloudflare.com/client/v4/accounts/$account_id/gateway/locations")
    if [[ -z $location_data ]]; then
        echo "Error: Unable to retrieve location data."
        exit 1
    fi
    echo "$location_data"
}

get_this_ip() {
    local ip=$(http_get "https://$ip_check_addr")
    
    # Check if the returned IP address is empty
    if [[ -z "$ip" ]]; then
        echo "Error: Unable to retrieve local IP address."
        exit 1
    fi
    
    # Use regex to validate the IP address format
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid IP address format: $ip"
        exit 1
    fi
    
    # Extract the first IPv4 address if there are multiple addresses
    ip=$(echo "$ip" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    
    echo "$ip"
}


put_network_addr() {
	# add new IP Address to Zero Trust Gateway Location
    local account_id="$1"
    local location="$2"
    local ipv4="$3"
	# https://developers.cloudflare.com/api/operations/zero-trust-gateway-locations-update-zero-trust-gateway-location
    http_put "https://api.cloudflare.com/client/v4/accounts/$account_id/gateway/locations/$location" "{ \"client_default\": false, \"ecs_support\": false, \"name\": \"$dns_location_name\", \"networks\": [{ \"network\": \"$ipv4/32\" }]}"
}

put_default_network_addr() {
	# add new IP Address to Zero Trust Gateway for DEFAULT Location 
    local account_id="$1"
    local location="$2"
    local ipv4="$3"
	# https://developers.cloudflare.com/api/operations/zero-trust-gateway-locations-update-zero-trust-gateway-location
    http_put "https://api.cloudflare.com/client/v4/accounts/$account_id/gateway/locations/$location" "{ \"client_default\": true, \"ecs_support\": false, \"name\": \"$dns_location_name\", \"networks\": [{ \"network\": \"$ipv4/32\" }]}"
}


# Check API key and get location ID data
check_api_key
location_id_data=$(get_location_data)

# Get the local IPv4 address
local_ipv4=$(get_this_ip)

# Extract network information for the DNS location
network=$(echo "$location_id_data" | jq -r --arg dns_location_name "$dns_location_name" '
    .result[]
    | select(.name == $dns_location_name)
    | if has("networks") then .networks[].network else empty end
')

# Get the location ID
location_id=$(echo "$location_id_data" | jq -r ".result[] | select(.name == \"$dns_location_name\") | .id")

# Get the default status of record
default_record=$(echo "$location_id_data" | jq -r ".result[] | select(.name == \"$dns_location_name\") | .client_default")


if [[ -n $network ]]; then
    network=$(echo "$network" | sed 's:/[0-9]\+$::')  # Remove subnet suffix
    echo "Current network for $dns_location_name: $network"
    if [[ "$network" == "$local_ipv4" ]]; then
        echo "Everything is up to date. Have a great day!"
        exit 0
    else
        echo "Local Network address: $local_ipv4"
        echo "New address detected..."
        if [[ "$default_record" == "true" ]]; then
        	local response=$(put_default_network_addr "$account_id" "$location_id" "$local_ipv4")
        else
	    	local response=$(put_network_addr "$account_id" "$location_id" "$local_ipv4")

        fi

        if [[ "$(echo "$response" | jq -r '.success')" == "true" ]]; then
            echo "Network address added successfully!  DNS is protected."
        else
            echo "Failed to update network address. Exiting..."
            exit 1
        fi
    fi
else
    echo "Network for $dns_location_name does not exist."

    if [[ "$default_record" == "true" ]]; then
    	response=$(put_default_network_addr "$account_id" "$location_id" "$local_ipv4")
    else
    	response=$(put_network_addr "$account_id" "$location_id" "$local_ipv4")

    fi

	success=$(echo "$response" | jq -r '.success')

	if [[ "$success" == "true" ]]; then
	    echo "Network address updated successfully! DNS is protected."
	    exit 0
	else
	    # Extract the error code and message from the response
	    error_code=$(echo "$response" | jq -r '.errors[0].code')
	    error_message=$(echo "$response" | jq -r '.errors[0].message')
	    echo "Failed to update network address. Error code: $error_code. Error message: $error_message"
	    exit 1
	fi
fi


