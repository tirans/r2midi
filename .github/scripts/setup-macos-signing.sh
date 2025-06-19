#!/bin/bash
# Certificate Setup Guide for R2MIDI macOS Signing
# This script helps you prepare the certificates for GitHub Actions

echo "🍎 R2MIDI macOS Code Signing Setup Guide"
echo "========================================"
echo ""
echo "This guide will help you set up the necessary certificates and secrets"
echo "for signing and notarizing R2MIDI macOS applications in GitHub Actions."
echo ""
echo "📋 Required Certificates:"
echo "• Developer ID Application (for signing apps)"
echo "• Developer ID Installer (for signing PKG installers)"
echo "• Both certificates are for distribution OUTSIDE the Mac App Store"
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to test P12 with OpenSSL 3.x compatibility
test_p12_certificate() {
    local cert_file="$1"
    local password="$2"
    
    # Try with -legacy flag first (OpenSSL 3.x)
    if openssl pkcs12 -legacy -in "$cert_file" -noout -passin pass:"$password" 2>/dev/null; then
        return 0
    # Try without -legacy flag (older OpenSSL)
    elif openssl pkcs12 -in "$cert_file" -noout -passin pass:"$password" 2>/dev/null; then
        return 0
    # Try with system OpenSSL
    elif [ -x "/usr/bin/openssl" ] && /usr/bin/openssl pkcs12 -in "$cert_file" -noout -passin pass:"$password" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check prerequisites
echo "📋 Checking prerequisites..."
missing_tools=()

if ! command_exists "security"; then
    missing_tools+=("macOS Keychain Access (security command)")
fi

if ! command_exists "openssl"; then
    missing_tools+=("OpenSSL")
fi

if ! command_exists "base64"; then
    missing_tools+=("base64")
fi

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo "❌ Missing required tools:"
    for tool in "${missing_tools[@]}"; do
        echo "  - $tool"
    done
    echo ""
    echo "Please install missing tools and run this script again."
    exit 1
fi

echo "✅ All required tools are available"

# Check OpenSSL version and warn about compatibility
echo "🔍 OpenSSL version: $(openssl version)"
if openssl version | grep -q "OpenSSL 3"; then
    echo "ℹ️  Note: OpenSSL 3.x detected - using legacy provider for P12 compatibility"
fi

echo ""

# Step 1: Apple Developer Program
echo "📝 Step 1: Apple Developer Program Enrollment"
echo "============================================="
echo ""
echo "Before you can create certificates, you need:"
echo "• An active Apple Developer Program membership (\$99/year)"
echo "• Access to Apple Developer Portal"
echo ""
echo "Have you enrolled in the Apple Developer Program? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo ""
    echo "Please enroll first:"
    echo "1. Go to https://developer.apple.com/programs/"
    echo "2. Click 'Enroll' and complete the process"
    echo "3. Wait for enrollment approval (can take 24-48 hours)"
    echo "4. Run this script again after enrollment is complete"
    exit 0
fi

echo ""

# Step 2: Certificate creation guide
echo "📝 Step 2: Create Certificates in Apple Developer Portal"
echo "======================================================="
echo ""
echo "Now we'll create the required certificates. Follow these exact steps:"
echo ""
echo "🔗 Go to: https://developer.apple.com/account/resources/certificates/list"
echo ""
echo "For DEVELOPER ID APPLICATION certificate:"
echo "----------------------------------------"
echo "1. Click the '+' button to 'Create a New Certificate'"
echo "2. Under 'Software' section, select:"
echo "   ☑️  Developer ID Application"
echo "   📝 'This certificate is used to code sign your app for distribution outside of the Mac App Store Connect.'"
echo "3. Click 'Continue'"
echo "4. You'll need a Certificate Signing Request (CSR) - we'll create this next"
echo ""
echo "For DEVELOPER ID INSTALLER certificate:"
echo "---------------------------------------"
echo "1. Repeat the process, but select:"
echo "   ☑️  Developer ID Installer"
echo "   📝 'This certificate is used to sign your app's Installer Package for distribution outside of the Mac App Store Connect.'"
echo "2. Click 'Continue'"
echo ""
echo "❗ IMPORTANT: Do NOT select these certificates:"
echo "   ❌ Apple Development (for development only)"
echo "   ❌ Apple Distribution (for App Store distribution)"
echo "   ❌ Mac App Distribution (for Mac App Store)"
echo "   ❌ Mac Installer Distribution (for Mac App Store)"
echo ""
echo "Have you opened the Apple Developer Portal in your browser? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo "Please open the portal first, then continue with this script."
    exit 0
fi

echo ""

# Step 3: CSR creation
echo "📝 Step 3: Create Certificate Signing Request (CSR)"
echo "==================================================="
echo ""
echo "Now we'll create a CSR using Keychain Access:"
echo ""
echo "1. Open 'Keychain Access' application"
echo "2. In the menu bar: Keychain Access → Certificate Assistant → Request a Certificate From a Certificate Authority"
echo "3. Fill in the form:"
echo "   • User Email Address: [Your Apple ID email]"
echo "   • Common Name: [Your name or organization]"
echo "   • CA Email Address: [Leave blank]"
echo "   • Request is: ☑️ Saved to disk"
echo "   • Let me specify key pair information: [Leave unchecked]"
echo "4. Click 'Continue'"
echo "5. Save the CSR file as 'CertificateSigningRequest.certSigningRequest'"
echo "6. Remember where you saved it!"
echo ""
echo "Have you created and saved the CSR file? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo "Please create the CSR first, then continue."
    exit 0
fi

echo ""

# Step 4: Upload CSR and download certificates
echo "📝 Step 4: Complete Certificate Creation"
echo "========================================"
echo ""
echo "Back in the Apple Developer Portal:"
echo ""
echo "For Developer ID Application certificate:"
echo "1. Upload your CSR file"
echo "2. Click 'Continue'"
echo "3. Click 'Download' to get the certificate"
echo "4. Double-click the downloaded certificate to install it in Keychain Access"
echo ""
echo "For Developer ID Installer certificate:"
echo "1. Start the process again (+ button)"
echo "2. Select 'Developer ID Installer'"
echo "3. Upload the SAME CSR file"
echo "4. Download and install this certificate too"
echo ""
echo "📋 You should now see both certificates in Keychain Access under 'My Certificates'"
echo ""
echo "Have you downloaded and installed both certificates? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo "Please complete the certificate installation first."
    exit 0
fi

echo ""

# Step 5: Verify certificates in Keychain
echo "📝 Step 5: Verify Certificates in Keychain"
echo "=========================================="
echo ""
echo "Let's verify your certificates are properly installed:"
echo ""
echo "1. Open Keychain Access"
echo "2. Select 'login' keychain (left sidebar)"
echo "3. Select 'My Certificates' category (left sidebar)"
echo "4. Look for these certificates:"
echo "   ✅ Developer ID Application: [Your Name] ([Team ID])"
echo "   ✅ Developer ID Installer: [Your Name] ([Team ID])"
echo "5. Each certificate should have a private key (arrow to expand)"
echo ""
echo "Can you see both certificates with their private keys? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo ""
    echo "❌ Certificates not found. Common issues:"
    echo "• Certificates installed in wrong keychain (should be 'login')"
    echo "• Private key missing (recreate CSR and certificates)"
    echo "• Certificate not downloaded properly"
    echo ""
    echo "Please verify the installation and try again."
    exit 1
fi

echo "✅ Certificates verified in Keychain"
echo ""

# Step 6: Export certificates
echo "📝 Step 6: Export Certificates from Keychain"
echo "============================================="
echo ""
echo "Now we'll export your certificates for GitHub Actions:"
echo ""
echo "Export Developer ID Application certificate:"
echo "1. In Keychain Access, find 'Developer ID Application: [Your Name]'"
echo "2. Click the arrow to expand and show the private key"
echo "3. Select BOTH the certificate AND the private key (Cmd+click both)"
echo "4. Right-click and choose 'Export 2 items...'"
echo "5. File format: 'Personal Information Exchange (.p12)'"
echo "6. Save as: 'app_cert.p12' in this directory ($(pwd))"
echo "7. Set a strong password (you'll need this for GitHub secrets)"
echo "8. Write down this password!"
echo ""
echo "Have you exported the Application certificate? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo "Please export the Application certificate first."
    exit 0
fi

if [ ! -f "app_cert.p12" ]; then
    echo "❌ app_cert.p12 not found in current directory"
    echo "Please ensure you exported the certificate to this location and try again."
    exit 1
fi

echo "✅ Application certificate exported"
echo ""

echo "Export Developer ID Installer certificate:"
echo "1. Find 'Developer ID Installer: [Your Name]' in Keychain Access"
echo "2. Expand to show certificate and private key"
echo "3. Select BOTH items and export as 'installer_cert.p12'"
echo "4. Use the SAME password as the Application certificate"
echo "5. Save in this directory: $(pwd)"
echo ""
echo "Have you exported the Installer certificate? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo "Please export the Installer certificate first."
    exit 0
fi

if [ ! -f "installer_cert.p12" ]; then
    echo "❌ installer_cert.p12 not found in current directory"
    echo "Please ensure you exported the certificate to this location and try again."
    exit 1
fi

echo "✅ Both certificate files found"
echo ""

# Step 7: Get certificate password
echo "📝 Step 7: Certificate Password Validation"
echo "=========================================="
echo ""
echo "Enter the password you used for the P12 certificates:"
echo "(This will be used to validate the certificates)"
read -s -r cert_password
echo ""

# Validate certificates with OpenSSL 3.x compatibility
echo "🔍 Validating certificates (OpenSSL 3.x compatible)..."
if ! test_p12_certificate "app_cert.p12" "$cert_password"; then
    echo "❌ Invalid Application certificate or password"
    echo "🔍 OpenSSL version: $(openssl version)"
    echo ""
    echo "This could be due to:"
    echo "• Incorrect password"
    echo "• Missing private key in export"
    echo "• OpenSSL 3.x compatibility issue (trying legacy provider...)"
    
    # Show detailed error for troubleshooting
    echo ""
    echo "Detailed error output:"
    openssl pkcs12 -legacy -in app_cert.p12 -noout -passin pass:"$cert_password" 2>&1 || \
    openssl pkcs12 -in app_cert.p12 -noout -passin pass:"$cert_password" 2>&1
    exit 1
fi

if ! test_p12_certificate "installer_cert.p12" "$cert_password"; then
    echo "❌ Invalid Installer certificate or password"
    echo "🔍 OpenSSL version: $(openssl version)"
    echo ""
    echo "Detailed error output:"
    openssl pkcs12 -legacy -in installer_cert.p12 -noout -passin pass:"$cert_password" 2>&1 || \
    openssl pkcs12 -in installer_cert.p12 -noout -passin pass:"$cert_password" 2>&1
    exit 1
fi

echo "✅ Both certificates validated successfully"
echo ""

# Step 8: Convert to base64
echo "📝 Step 8: Converting to Base64"
echo "==============================="
echo ""
echo "Converting certificates to base64 format for GitHub secrets..."

app_cert_base64=$(base64 -i app_cert.p12)
installer_cert_base64=$(base64 -i installer_cert.p12)

echo "✅ Certificates converted to base64"
echo ""

# Continue with the rest of the script (Steps 9-13 remain the same as before)
# [The rest remains unchanged from the previous version]

# Step 9: App-specific password for notarization
echo "📝 Step 9: App-Specific Password for Notarization"
echo "================================================="
echo ""
echo "For notarization, you need an app-specific password:"
echo ""
echo "🔗 Go to: https://appleid.apple.com/"
echo ""
echo "1. Sign in with your Apple ID"
echo "2. In the 'Security' section, find 'App-Specific Passwords'"
echo "3. Click 'Generate Password...'"
echo "4. Enter a label: 'R2MIDI macOS Notarization'"
echo "5. Copy the generated password (format: xxxx-xxxx-xxxx-xxxx)"
echo ""
echo "❗ This password is shown only once - copy it carefully!"
echo ""
echo "Have you created the app-specific password? (y/n)"
read -r response
if [[ ! "$response" =~ ^[Yy] ]]; then
    echo "Please create the app-specific password first."
    exit 0
fi

echo ""
echo "Enter your app-specific password:"
read -s -r app_password
echo ""

echo "Enter your Apple ID (email address):"
read -r apple_id

# Step 10: Get Team ID
echo ""
echo "📝 Step 10: Find Your Team ID"
echo "============================="
echo ""
echo "Your Team ID is needed for notarization:"
echo ""
echo "🔗 Go to: https://developer.apple.com/account/#!/membership/"
echo ""
echo "Look for 'Team ID' - it's a 10-character alphanumeric string"
echo "Example: ABC123DEFG"
echo ""
echo "Enter your Apple Team ID:"
read -r team_id

# Validate Team ID format
if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "⚠️ Warning: Team ID should be 10 characters (letters and numbers)"
    echo "Please double-check your Team ID. Continue anyway? (y/n)"
    read -r response
    if [[ ! "$response" =~ ^[Yy] ]]; then
        echo "Please verify your Team ID and run the script again."
        exit 0
    fi
fi

echo ""

# Step 11: Generate GitHub secrets
echo "📝 Step 11: GitHub Repository Secrets"
echo "===================================="
echo ""
echo "Now we'll generate the secrets for your GitHub repository."
echo ""

cat > github_secrets.txt << EOF
GitHub Repository Secrets for R2MIDI macOS Signing
==================================================

Add these secrets to your GitHub repository:
Go to: Settings > Secrets and variables > Actions > New repository secret

CRITICAL: Copy these values EXACTLY as shown below.

Secret Name: APPLE_DEVELOPER_ID_APPLICATION_CERT
Secret Value:
$app_cert_base64

Secret Name: APPLE_DEVELOPER_ID_INSTALLER_CERT
Secret Value:
$installer_cert_base64

Secret Name: APPLE_CERT_PASSWORD
Secret Value:
$cert_password

Secret Name: APPLE_ID
Secret Value:
$apple_id

Secret Name: APPLE_ID_PASSWORD
Secret Value:
$app_password

Secret Name: APPLE_TEAM_ID
Secret Value:
$team_id

Setup Instructions:
==================

1. Go to your GitHub repository: https://github.com/[your-username]/r2midi
2. Click: Settings > Secrets and variables > Actions
3. For each secret above:
   - Click "New repository secret"
   - Enter the exact Secret Name
   - Paste the exact Secret Value
   - Click "Add secret"

4. Verify all 6 secrets are added:
   ✅ APPLE_DEVELOPER_ID_APPLICATION_CERT
   ✅ APPLE_DEVELOPER_ID_INSTALLER_CERT
   ✅ APPLE_CERT_PASSWORD
   ✅ APPLE_ID
   ✅ APPLE_ID_PASSWORD
   ✅ APPLE_TEAM_ID

Testing Your Setup:
==================

After adding secrets:
1. Push a commit to trigger the macOS build workflow
2. Check GitHub Actions for build success
3. Look for signed .dmg and .pkg files in artifacts

OpenSSL Compatibility:
====================

Your certificates use RC2-40-CBC encryption (common with Keychain Access exports).
The updated scripts automatically handle OpenSSL 3.x compatibility using the legacy provider.

Certificate Details:
==================

Application Certificate: Developer ID Application
- Purpose: Sign macOS applications for distribution outside Mac App Store
- Used by: codesign command

Installer Certificate: Developer ID Installer  
- Purpose: Sign PKG installers for distribution outside Mac App Store
- Used by: productsign command

Security Notes:
==============

- These secrets provide access to your Apple Developer certificates
- Only add them to repositories you trust completely
- Regenerate app-specific password if compromised
- Store this file securely and delete after GitHub setup
- Never commit certificate files to git

Generated: $(date)
Valid until: [Check certificate expiration in Keychain Access]
EOF

echo "✅ GitHub secrets saved to 'github_secrets.txt'"
echo ""

# Final steps (cleanup, etc.) remain the same as before...
echo "📝 Step 12: Security Cleanup (Recommended)"
echo "=========================================="
echo ""
echo "For security, you should clean up the certificate files:"
echo ""
echo "Files to delete after GitHub setup:"
echo "• app_cert.p12 (contains private key)"
echo "• installer_cert.p12 (contains private key)"
echo "• github_secrets.txt (contains passwords)"
echo ""
echo "⚠️ Keep the original certificates in Keychain Access for future use"
echo ""
echo "Delete certificate files now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy] ]]; then
    rm -f app_cert.p12 installer_cert.p12
    echo "✅ Certificate files deleted"
    echo "📋 Remember to delete 'github_secrets.txt' after GitHub setup"
else
    echo "⚠️ Remember to delete the certificate files manually after GitHub setup"
fi

echo ""
echo "🎉 macOS Code Signing Setup Complete!"
echo "====================================="
echo ""
echo "✅ Your certificates are valid and compatible with OpenSSL 3.x"
echo "✅ GitHub secrets are ready to be added to your repository"
echo "✅ Updated scripts handle OpenSSL compatibility automatically"
echo ""
echo "📋 Next: Add the secrets to GitHub and test your build!"
