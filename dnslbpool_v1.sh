#!/bin/bash

# Declare associative arrays
declare -A pool_list
declare -A membersip_array

# Get list of wide IPs
output=$(tmsh list gtm pool a one-line all-properties)

# Loop through each line of output
while IFS= read -r line; do
    pool_name=$(awk '{print $4}' <<< "$line")
	  dnslbpool_name=$(echo "$pool_name" | sed 's/[^a-zA-Z0-9]/-/g; s/.*/\L&/')
    type=$(awk '{print $3}' <<< "$line")
    lbmode=$(grep -o 'load-balancing-mode [^ ]*' <<< "$line" | awk '{print $2}')
    
    # Extract members block using awk
    members=$(awk -F 'members {| }' '{print $2}' <<< "$line")
    membersip=$(awk '{print $1}' <<< "$members")
    
    # Temporary array to hold member IP addresses
    declare -a temp_members_array
    temp_members_array=($(awk -F ':' '{print $2}' <<< "$membersip"))

    monitor=$(awk -F 'monitor ' '{print $2}' <<< "$line" | awk '{print $1}')
    ttl=$(awk '{print $2}' <<< "$(grep -o 'ttl [^ ]*' <<< "$line")")
    
    # Assign values to the associative array
    membersip_array["$dnslbpool_name"]="${temp_members_array[@]}"

    # Store extracted values in the array
    pool_list["$dnslbpool_name"]="type: $type, lbmode: $lbmode, monitor: $monitor, members: ${membersip_array["$dnslbpool_name"]}, ttl: $ttl"
done <<< "$output"

# Display the array content
declare -p pool_list

for dnslbpool_name in "${!pool_list[@]}"; do
    # Example curl command using pool information
	curl -X POST -H "Authorization: APIToken Rs0aGJm/lda/JmbE00c9lFXWw4I=" -H "Accept: application/json" -H "Access-Control-Allow-Origin: *" -H "x-volterra-apigw-tenant: cag-waap2023" -H "Content-Type: application/json" -d "{\"metadata\":{\"name\":\"$dnslbpool_name\",\"namespace\":\"system\"},\"spec\":{\"a_pool\":{\"members\":[{\"ip_endpoint\":\"1.2.3.4\",\"ratio\":10,\"priority\":1}],\"disable_health_check\":null,\"max_answers\":1},\"ttl\":300}}" "https://cag-waap2023.console.ves.volterra.io/api/config/dns/namespaces/system/dns_lb_pools"
done

# Unset variables to free up memory
unset pool_list membersip_array
