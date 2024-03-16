# cloudflare_helpers
Collection of helper scripts to manage Cloudflare services


> Each service contains an example `secrets.txt.example` file that needs to be renamed to `secrets.txt` and filled out

## Zero Trust Gateway DNS Record Update

Update the local IP address for the [zeroTrust gateway DNS locations](https://developers.cloudflare.com/cloudflare-one/connections/connect-devices/agentless/dns/locations/) based on assigned dynamic public address.

This was developed to accomplish the continued protection of the DNS filtering rules with cloudflare after an ISP forced public address change. This continues the protection provided through cloudflare zeroTrust.

### Requirements

- Linux/Unix (tested on Ubuntu 22.04)
- Cloudflare account, with zeroTrust DNS filtering setup and functional. (DNS filtering out of scope here, see [cloudflare docs](https://developers.cloudflare.com/cloudflare-one/))
- `jq` installed on the local system `sudo apt install jq`
-  API key that allows `Account|Zero Trust|Edit` permissions for the account
- Cloudflare account ID (Found in the url while logged in, or under any website overview, "Account ID")


### Secrets.txt

Enter your info in the secrets file, ensure the values are "quoted".

### Execution Permissions

Give the `zeroTrust_gateway_ip_update.sh`  the old execute permissions massage. From the repo root folder:

`chmod +x ./ZeroTrust/zeroTrust_gateway_ip_update.sh`

### Execute the Script

If everything is done, test the script. It should find the gateway DNS location and update it with the current IP address of the device the script is ran on.

### crontab

Add the script to the crontab folder with the following (edit for your location). This runs every 10 min.

`*/10 * * * *	/home/$USER/cloudflare_helpers/ZeroTrust/zeroTrust_gateway_ip_updates.sh`

> **Note** This script updates every thime it runs to pickup any changes here in this repo.


## DNS Record Update

Update the IP address for the a cloudflare sub domain.

This was heavily re-used from [this gist](https://gist.github.com/Tras2/cba88201b17d765ec065ccbedfb16d9a), thanks for the great work!


### Requirements

- Linux/Unix (tested on Ubuntu 22.04)
- Cloudflare account, with a domain DNS hosted with cloudflare
- Subdomain entry for record to update
- `jq` installed on the local system `sudo apt install jq`
-  API key that allows `ZOND|EDIT|zone_to_edit` permissions for the domain to edit `API_TOKEN`
- Cloudflare user email associated to the key `EMAIL`
- Domain name for record to edit `DOMAIN.TLD`
- FQDN for the record `HOST.DOMAIN.TLD`

### Secrets.txt

Enter your info in the secrets file, ensure the values are "quoted".

### Execution Permissions

Give the `cloudflare_dns_update.sh`  the old execute permissions massage. From the repo root folder:

`chmod +x ./DNS/cloudflare_dns_update.sh`

### Execute the Script

If everything is done, test the script. It should find the gateway DNS location and update it with the current IP address of the device the script is ran on.

### crontab

Add the script to the crontab folder with the following (edit for your location). This runs every 10 min.

`*/10 * * * *	/home/$USER/cloudflare_helpers/DNS/cloudflare_dns_update.sh`