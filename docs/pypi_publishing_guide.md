# PyPI Publishing Guide for R2MIDI

## Overview

This guide explains how to publish the R2MIDI package to PyPI using GitHub Actions. It covers the two authentication methods available and how to troubleshoot common issues.

## Authentication Methods

There are two methods for authenticating with PyPI when publishing packages:

### 1. API Token Authentication (Current Method)

This method uses a PyPI API token to authenticate with PyPI. It's simpler to set up but requires managing a secret token.

**Required configuration:**
- A PyPI API token stored as a GitHub secret
- The `password` parameter in the PyPI publishing action

### 2. Trusted Publishing (OpenID Connect)

This method uses OpenID Connect (OIDC) to authenticate with PyPI without needing to store a token. It's more secure but requires additional configuration on both GitHub and PyPI.

**Required configuration:**
- The `id-token: write` permission in the workflow
- A trusted publisher configuration in PyPI
- No `password` parameter in the PyPI publishing action

## Current Configuration

The R2MIDI project is currently configured to use the API Token Authentication method. This was chosen because:

1. It's simpler to set up and maintain
2. It doesn't require additional configuration on the PyPI side
3. It's compatible with all PyPI accounts

## Troubleshooting

### "Trusted publishing exchange failure" Error

If you see an error like this:

```
Error: Trusted publishing exchange failure: 
Token request failed: the server refused the request for the following reasons:

* `invalid-publisher`: valid token, but no corresponding publisher (All lookup strategies exhausted)
```

This indicates that the workflow is trying to use trusted publishing, but there's no corresponding publisher configuration in PyPI. This can happen if:

1. The workflow has the `id-token: write` permission but you haven't set up trusted publishing in PyPI
2. The workflow is using both the `id-token: write` permission and the `password` parameter

**Solution:**
- If you want to use API token authentication, remove the `id-token: write` permission from the workflow
- If you want to use trusted publishing, set up a trusted publisher in PyPI and remove the `password` parameter

## Setting Up API Token Authentication

1. Create a PyPI API token:
   - Go to https://pypi.org/manage/account/
   - Click "Add API token"
   - Give it a name (e.g., "GitHub Actions")
   - Set the scope to "Entire account" or specific projects
   - Click "Create token"
   - Copy the token (you won't be able to see it again)

2. Add the token as a GitHub secret:
   - Go to your GitHub repository
   - Click "Settings" > "Secrets and variables" > "Actions"
   - Click "New repository secret"
   - Name: `PYPI_API_TOKEN`
   - Value: Paste the token you copied
   - Click "Add secret"

3. Configure the workflow:
   - Make sure the workflow does NOT have the `id-token: write` permission
   - Make sure the PyPI publishing action uses the `password` parameter with the secret

## Setting Up Trusted Publishing

If you want to switch to trusted publishing in the future, follow these steps:

1. Configure the workflow:
   - Add the `id-token: write` permission to the workflow
   - Remove the `password` parameter from the PyPI publishing action

2. Set up a trusted publisher in PyPI:
   - Go to https://pypi.org/manage/account/
   - Click "Add publisher"
   - Select "GitHub Actions"
   - Enter your repository details:
     - Owner: `tirans`
     - Repository: `r2midi`
     - Workflow name: `.github/workflows/release.yml`
     - Environment: `pypi`
   - Click "Add"

## Further Resources

- [PyPI Trusted Publishing Documentation](https://docs.pypi.org/trusted-publishers/)
- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-cloud-providers)
- [PyPA gh-action-pypi-publish Documentation](https://github.com/pypa/gh-action-pypi-publish)