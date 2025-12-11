#!/bin/bash
# Generate cat << EOF commands for radosgw-admin scripts
# This allows creating files in the pod without vi

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Commands to create radosgw-admin scripts in pod ==="
echo ""
echo "Copy and paste these commands into the pod:"
echo ""

# Function to generate cat command for a script
generate_cat_command() {
    local script_file="$1"
    local script_name=$(basename "$script_file")
    
    echo "# Create $script_name"
    echo "cat > /tmp/$script_name << 'ENDOFFILE'"
    cat "$script_file"
    echo "ENDOFFILE"
    echo "chmod +x /tmp/$script_name"
    echo ""
}

# Generate commands for radosgw-admin scripts
echo "=== Core radosgw-admin scripts ==="
generate_cat_command "$SCRIPTS_DIR/check-bucket-size.sh"
generate_cat_command "$SCRIPTS_DIR/inspect-bucket-json.sh"
generate_cat_command "$SCRIPTS_DIR/delete-objects-by-date.sh"
generate_cat_command "$SCRIPTS_DIR/cleanup-buckets-by-date.sh"

echo "=== Diagnostic scripts ==="
generate_cat_command "$SCRIPTS_DIR/fix-bucket-stats-command.sh"
generate_cat_command "$SCRIPTS_DIR/debug-bucket-stats.sh"

echo "=== All scripts created in /tmp/ ==="
echo "You can now run them with: /tmp/script-name.sh"
