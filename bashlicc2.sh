#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    printf "${1}${2}${NC}\n"
}

# RHEL License mapping
declare -A RHEL_LICENSES=(
    ["1000002"]="RHEL 6 PAYG"
    ["4720191914037931587"]="RHEL 6 BYOS"
    ["1000006"]="RHEL 7 PAYG"
    ["1492188837615955530"]="RHEL 7 BYOS"
    ["4646774207868449156"]="RHEL 7 ELS"
    ["601259152637613565"]="RHEL 8 PAYG"
    ["8475125252192923229"]="RHEL 8 BYOS"
    ["7883559014960410759"]="RHEL 9 PAYG"
    ["3837518230911135854"]="RHEL 9 BYOS"
    ["1270685562947480748"]="RHEL 8 for SAP PAYG"
    ["489291035512960571"]="RHEL 8 for SAP BYOS"
    ["8291906032809750558"]="RHEL 9 for SAP PAYG"
    ["6753525580035552782"]="RHEL 9 for SAP BYOS"
)

# Check if gcloud is installed
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_color $RED "Error: gcloud CLI is not installed."
        print_color $YELLOW "Please install gcloud CLI: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    print_color $GREEN "✓ gcloud CLI found"
}

# Authenticate to GCP
authenticate_gcp() {
    print_color $BLUE "Authenticating to Google Cloud Platform..."
    
    # Check if already authenticated
    if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        print_color $GREEN "✓ Already authenticated to GCP"
        current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
        print_color $BLUE "Current account: $current_account"
        
        read -p "Do you want to use this account? (y/n): " use_current
        if [[ $use_current != "y" && $use_current != "Y" ]]; then
            gcloud auth login
        fi
    else
        gcloud auth login
    fi
}

# Get organization folders
get_organization_folders() {
    print_color $BLUE "Fetching organization folders..."
    
    # Get organization ID
    org_id=$(gcloud organizations list --format="value(name)" | head -1)
    if [[ -z "$org_id" ]]; then
        print_color $RED "Error: No organization found or insufficient permissions"
        exit 1
    fi
    
    print_color $GREEN "✓ Organization found: $org_id"
    
    # Get folders, excluding system-gsuite
    folders=$(gcloud resource-manager folders list --organization="$org_id" --format="table(name,displayName)" --filter="displayName!='system-gsuite'" | tail -n +2)
    
    if [[ -z "$folders" ]]; then
        print_color $RED "No folders found in organization"
        exit 1
    fi
    
    echo "$folders"
}

# Select folder
select_folder() {
    local folders="$1"
    print_color $BLUE "\nAvailable folders:"
    
    # Create arrays for folder names and display names
    declare -a folder_ids
    declare -a folder_names
    local i=1
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            folder_id=$(echo "$line" | awk '{print $1}')
            folder_name=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
            folder_ids+=("$folder_id")
            folder_names+=("$folder_name")
            printf "%d) %s\n" "$i" "$folder_name"
            ((i++))
        fi
    done <<< "$folders"
    
    while true; do
        read -p "Select folder number (1-$((i-1))): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le $((i-1)) ]]; then
            selected_folder_id="${folder_ids[$((selection-1))]}"
            selected_folder_name="${folder_names[$((selection-1))]}"
            print_color $GREEN "✓ Selected folder: $selected_folder_name"
            break
        else
            print_color $RED "Invalid selection. Please try again."
        fi
    done
}

# Get projects and subfolders in selected folder
get_folder_contents() {
    local folder_id="$1"
    print_color $BLUE "Fetching contents of selected folder..."
    
    # Get subfolders
    subfolders=$(gcloud resource-manager folders list --folder="$folder_id" --format="table(name,displayName)" 2>/dev/null | tail -n +2)
    
    # Get projects
    projects=$(gcloud projects list --filter="parent.id='$folder_id'" --format="table(projectId,name)" 2>/dev/null | tail -n +2)
    
    if [[ -z "$subfolders" && -z "$projects" ]]; then
        print_color $RED "No projects or subfolders found in selected folder"
        exit 1
    fi
    
    print_color $BLUE "\nContents of selected folder:"
    
    declare -a all_items
    declare -a item_types
    declare -a item_ids
    local i=1
    
    # Add subfolders
    if [[ -n "$subfolders" ]]; then
        print_color $YELLOW "Subfolders:"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                folder_id=$(echo "$line" | awk '{print $1}')
                folder_name=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
                all_items+=("$folder_name")
                item_types+=("folder")
                item_ids+=("$folder_id")
                printf "  %d) [FOLDER] %s\n" "$i" "$folder_name"
                ((i++))
            fi
        done <<< "$subfolders"
    fi
    
    # Add projects
    if [[ -n "$projects" ]]; then
        print_color $YELLOW "Projects:"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                project_id=$(echo "$line" | awk '{print $1}')
                project_name=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
                all_items+=("$project_name")
                item_types+=("project")
                item_ids+=("$project_id")
                printf "  %d) [PROJECT] %s\n" "$i" "$project_name"
                ((i++))
            fi
        done <<< "$projects"
    fi
    
    echo ""
    printf "%d) [ALL] Search all folders and projects\n" "$i"
    
    while true; do
        read -p "Select item number (1-$i): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$i" ]]; then
            if [[ "$selection" -eq "$i" ]]; then
                # Select all
                search_scope="all"
                print_color $GREEN "✓ Will search all folders and projects"
            else
                # Select specific item
                selected_item="${all_items[$((selection-1))]}"
                selected_type="${item_types[$((selection-1))]}"
                selected_id="${item_ids[$((selection-1))]}"
                search_scope="single"
                print_color $GREEN "✓ Selected: $selected_item (${selected_type})"
            fi
            break
        else
            print_color $RED "Invalid selection. Please try again."
        fi
    done
}

# Check disk licenses for RHEL
check_disk_licenses() {
    local project_id="$1"
    local vm_name="$2"
    local zone="$3"
    
    # Get disk information for the VM
    local disks=$(gcloud compute instances describe "$vm_name" --zone="$zone" --project="$project_id" --format="value(disks[].source)" 2>/dev/null)
    
    if [[ -z "$disks" ]]; then
        return
    fi
    
    # Check each disk for licenses
    while IFS= read -r disk_url; do
        if [[ -n "$disk_url" ]]; then
            # Extract disk name and zone from the URL
            local disk_name=$(basename "$disk_url")
            local disk_zone=$(echo "$disk_url" | sed -n 's|.*/zones/\([^/]*\)/.*|\1|p')
            
            # Get disk details including licenses
            local disk_info=$(gcloud compute disks describe "$disk_name" --zone="$disk_zone" --project="$project_id" --format="json" 2>/dev/null)
            
            if [[ -n "$disk_info" ]]; then
                # Extract license URLs from the JSON
                local licenses=$(echo "$disk_info" | jq -r '.licenses[]?' 2>/dev/null)
                
                if [[ -n "$licenses" ]]; then
                    while IFS= read -r license_url; do
                        if [[ -n "$license_url" ]]; then
                            # Extract license code from URL (last part after the last slash)
                            local license_code=$(basename "$license_url")
                            
                            # Check if this license code matches any RHEL license
                            if [[ -n "${RHEL_LICENSES[$license_code]}" ]]; then
                                print_color $GREEN "VM instance $project_id:$vm_name has the ${RHEL_LICENSES[$license_code]} License"
                            fi
                        fi
                    done <<< "$licenses"
                fi
            fi
        fi
    done <<< "$disks"
}

# Get VM instances from projects
get_vm_instances() {
    print_color $BLUE "Searching for VM instances..."
    
    declare -a vm_list
    declare -a project_list
    
    if [[ "$search_scope" == "all" ]]; then
        # Search all projects in the folder
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                project_id=$(echo "$line" | awk '{print $1}')
                project_list+=("$project_id")
            fi
        done <<< "$projects"
    elif [[ "$selected_type" == "project" ]]; then
        project_list+=("$selected_id")
    else
        print_color $YELLOW "Folder selected. Recursively searching for projects..."
        # For folders, we'd need to implement recursive search
        print_color $RED "Recursive folder search not implemented in this version"
        exit 1
    fi
    
    print_color $BLUE "Scanning ${#project_list[@]} project(s) for VM instances..."
    
    for project_id in "${project_list[@]}"; do
        print_color $BLUE "Checking project: $project_id"
        
        # Set the project
        gcloud config set project "$project_id" &>/dev/null
        
        # Get VM instances with more details
        vms=$(gcloud compute instances list --format="csv(name,zone,status)" --quiet 2>/dev/null | tail -n +2)
        
        if [[ -n "$vms" ]]; then
            while IFS= read -r vm_line; do
                if [[ -n "$vm_line" ]]; then
                    vm_list+=("$project_id: $vm_line")
                fi
            done <<< "$vms"
        fi
    done
    
    if [[ ${#vm_list[@]} -eq 0 ]]; then
        print_color $RED "No VM instances found"
        exit 0
    fi
    
    print_color $GREEN "Found ${#vm_list[@]} VM instance(s):"
    for vm in "${vm_list[@]}"; do
        echo "  - $vm"
    done
}

# Search for RHEL licenses
search_rhel_licenses() {
    print_color $BLUE "\nSearching for RHEL licenses on VM instances..."
    
    declare -a vm_list
    declare -a project_list
    
    if [[ "$search_scope" == "all" ]]; then
        # Search all projects in the folder
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                project_id=$(echo "$line" | awk '{print $1}')
                project_list+=("$project_id")
            fi
        done <<< "$projects"
    elif [[ "$selected_type" == "project" ]]; then
        project_list+=("$selected_id")
    else
        print_color $YELLOW "Folder selected. Recursively searching for projects..."
        # For folders, we'd need to implement recursive search
        print_color $RED "Recursive folder search not implemented in this version"
        exit 1
    fi
    
    local rhel_licenses_found=0
    
    for project_id in "${project_list[@]}"; do
        print_color $BLUE "Scanning project $project_id for RHEL licenses..."
        
        # Set the project
        gcloud config set project "$project_id" &>/dev/null
        
        # Get VM instances with zone information
        local vms=$(gcloud compute instances list --format="csv(name,zone,status)" --quiet 2>/dev/null | tail -n +2)
        
        if [[ -n "$vms" ]]; then
            while IFS=',' read -r vm_name zone status; do
                if [[ -n "$vm_name" && -n "$zone" ]]; then
                    # Remove quotes if present
                    vm_name=$(echo "$vm_name" | tr -d '"')
                    zone=$(echo "$zone" | tr -d '"')
                    status=$(echo "$status" | tr -d '"')
                    
                    # Count RHEL licenses found
                    local licenses_before=$rhel_licenses_found
                    check_disk_licenses "$project_id" "$vm_name" "$zone"
                    # Note: We'll need to modify check_disk_licenses to return a count
                fi
            done <<< "$vms"
        fi
    done
    
    print_color $BLUE "\nRHEL license scan completed."
}

# Ask about license search
ask_license_search() {
    echo ""
    read -p "Would you like to search these VMs for RHEL licenses? (y/n): " search_licenses
    
    if [[ $search_licenses == "y" || $search_licenses == "Y" ]]; then
        search_rhel_licenses
    else
        print_color $BLUE "Skipping license search"
    fi
}

# Main execution
main() {
    print_color $GREEN "=== GCP VM Instance Discovery and RHEL License Scanner ==="
    
    # Check if jq is installed (needed for JSON parsing)
    if ! command -v jq &> /dev/null; then
        print_color $RED "Error: jq is not installed."
        print_color $YELLOW "Please install jq for JSON parsing: sudo apt-get install jq (or equivalent for your OS)"
        exit 1
    fi
    
    check_gcloud
    authenticate_gcp
    
    folders=$(get_organization_folders)
    select_folder "$folders"
    get_folder_contents "$selected_folder_id"
    get_vm_instances
    ask_license_search
    
    print_color $GREEN "Script completed successfully!"
}

# Run the script
main "$@"