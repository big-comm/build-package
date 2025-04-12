# Community Package Build Action

This repository contains GitHub Actions workflows and a custom action for building and managing packages for the Community repository. The system is designed to handle both AUR (Arch User Repository) packages and custom community packages.

## Table of Contents

1. [Overview](#overview)
2. [Workflows](#workflows)
   - [AUR Package Build](#aur-package-build)
   - [Build Package](#build-package)
3. [Custom Action](#custom-action)
4. [Usage](#usage)
5. [Input Parameters](#input-parameters)
6. [Environment Variables](#environment-variables)
7. [Secrets](#secrets)
8. [Workflow Steps](#workflow-steps)
9. [Customization](#customization)
10. [Contributing](#contributing)
11. [License](#license)

## Overview

This project automates the process of building, signing, and publishing packages for the Community repository. It supports both AUR packages and custom community packages, with different workflows for each type.

## Workflows

### AUR Package Build

**File:** `aur-package-build.yml`

This workflow is triggered by repository dispatch events with types starting with 'aur-*' or manually through the workflow dispatch. It's designed to build packages from the Arch User Repository (AUR).

Key features:
- Supports manual and automated triggering
- Uses a custom Docker container for the build environment
- Handles AUR package building, signing, and publishing
- Supports debug sessions with tmate
- Integrates with Telegram for notifications

### Build Package

**File:** `build-package.yml`

This workflow is for building custom community packages. It can be triggered by repository dispatch events (except those starting with 'aur-*') or manually through the workflow dispatch.

Key features:
- Supports multiple branch types (testing, extra, stable)
- Allows creation of new branches
- Uses a custom Docker container for the build environment
- Handles package building, signing, and publishing
- Supports debug sessions with tmate
- Integrates with Telegram for notifications

## Custom Action

**File:** `action.yml`

This is the core action used by both workflows. It defines the steps for building, signing, and publishing packages.

Key features:
- Configurable build environment
- Support for custom package repositories
- GPG signing of packages
- Publishing to GitHub releases
- Pushing to custom package repositories
- Updating repository databases
- Cleaning old packages

## Usage

To use these workflows and the custom action in your repository:

1. Copy the workflow files (`aur-package-build.yml` and `build-package.yml`) to your `.github/workflows/` directory.
2. Copy the `action.yml` file to the root of your repository.
3. Set up the required secrets in your GitHub repository settings.
4. Trigger the workflows manually or set up repository dispatch events to automate the process.

## Input Parameters

The custom action supports the following input parameters:

- `build_env`: Build environment (testing, extra, stable, or aur)
- `source`: Custom package repo source
- `manjaro_branch`: Manjaro branch to build
- `custom_repo`: Custom repo
- `multilib`: Build multilib package
- `repo`: Package repo
- `gpg_key`: GPG signing key
- `gpg_passphrase`: GPG passphrase
- `git_branch`: Extra repository to build package
- `extra_command`: Extra command to run before building
- `extra_package`: Extra package to build
- `tmate`: Run tmate for debugging
- `repo_mirror`: Mirror to use in build
- `repo_dev`: Development repository
- `pacman_mirror`: Specific mirror to override automatic selection
- `publish_github`: Publish package on GitHub
- `push_to_repo`: Push package to repository
- `update_db`: Update repository database
- `repo_host`: Repository host
- `repo_user`: Repository user
- `repo_port`: Repository port
- `repo_dir`: Repository directory
- `github_token`: GitHub token for authentication
- `telegram_token`: Telegram bot token for notifications
- `telegram_chat_id`: Telegram chat ID for notifications
- `branch_type`: Branch type (testing or stable)
- `url`: Repository URL
- `new_branch`: Name of the new branch
- `package_name`: Package name
- `aur_package_dir`: Directory containing the AUR package

## Environment Variables

The workflows use the following environment variables:

- `PACKAGE_NAME`: Name of the package to build
- `AUR_URL`: URL of the AUR package
- `BRANCH_TYPE`: Type of branch (aur, testing, extra, stable)
- `BUILD_ENV`: Build environment
- `NEW_BRANCH`: Name of the new branch to create or use

## Secrets

The following secrets are required:

- `PKGBUILD_KEY`: SSH key for accessing the package build server
- `GITHUB_TOKEN`: GitHub authentication token
- `GPG_PRIVATE_KEY`: GPG private key for signing packages
- `PASSPHRASE`: Passphrase for the GPG key
- `TOKEN_BOT`: Telegram bot token
- `CHAT_ID`: Telegram chat ID for notifications
- `PKGBUILD_HOST`: Hostname of the package build server
- `PKGBUILD_USER`: Username for the package build server
- `PKGBUILD_PORT`: SSH port for the package build server
- `PKGBUILD_DIR`: Directory on the build server for storing packages

## Workflow Steps

Both workflows follow a similar pattern:

1. Checkout the repository
2. Set up SSH agent
3. Set environment variables
4. Fetch all branches (for custom packages)
5. Checkout or create the specified branch (for custom packages)
6. Set up debug session with tmate (if enabled)
7. Run the custom action to build and publish the package
8. Clean up

The custom action performs the following steps:

1. Setup build environment
2. Configure system and repositories
3. Download source code
4. Build package
5. Sign package
6. Generate checksums
7. Publish package on GitHub (if enabled)
8. Push to repository (if enabled)
9. Update repository database (if enabled)
10. Clean old packages (if enabled)

## Customization

You can customize the build process by:

- Modifying the `action.yml` file to add or remove steps
- Adjusting the input parameters in the workflow files
- Changing the Docker image used for the build environment
- Adding custom commands in the `extra_command` input

## Contributing

Contributions to improve the workflows or the custom action are welcome. Please submit pull requests or open issues to discuss potential changes or improvements.

## License

[Insert your license information here]
