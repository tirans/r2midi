import logging
import os
import re
import shutil

import git
from git import GitCommandError, Repo

# Configure logger
logger = logging.getLogger(__name__)


def get_midi_presets_mode():
    """
    Determine the mode for handling midi-presets based on R2MIDI_ROLE environment variable

    Returns:
        str: 'clone' for release mode (default), 'submodule' for dev mode
    """
    role = os.environ.get("R2MIDI_ROLE", "release").lower()

    if role == "dev":
        logger.info("R2MIDI_ROLE=dev: Using submodule mode for midi-presets")
        return "submodule"
    else:
        logger.info(f"R2MIDI_ROLE={role}: Using clone mode for midi-presets")
        return "clone"


def ensure_midi_presets_clone():
    """
    Ensure midi-presets exists as a cloned repository (for release mode)

    Returns:
        Tuple of (success: bool, message: str, status_code: int)
    """
    logger.info("Ensuring midi-presets exists as a cloned repository")

    try:
        # Get the server directory (where this file is located)
        server_dir = os.path.dirname(__file__)
        midi_presets_dir = os.path.join(server_dir, "midi-presets")
        midi_presets_url = "https://github.com/tirans/midi-presets.git"

        # Check if directory exists
        if os.path.exists(midi_presets_dir):
            # Check if it's a git repository
            try:
                repo = Repo(midi_presets_dir)

                # Check if it's a submodule (has .git file instead of directory)
                git_path = os.path.join(midi_presets_dir, ".git")
                if os.path.isfile(git_path):
                    logger.info(
                        "Found submodule, converting to regular clone for release mode"
                    )

                    # Remove the submodule
                    shutil.rmtree(midi_presets_dir)

                    # Clone fresh
                    logger.info(f"Cloning {midi_presets_url} to {midi_presets_dir}")
                    Repo.clone_from(midi_presets_url, midi_presets_dir)
                    logger.info("Successfully cloned midi-presets repository")
                else:
                    # It's a regular repository, check for unstaged changes before pulling
                    logger.info("Found existing clone, checking for unstaged changes")

                    # Check if there are unstaged changes
                    status_output = repo.git.status(porcelain=True)
                    if status_output.strip():
                        logger.info(
                            "Found unstaged changes, committing them before pulling"
                        )
                        # Add all changes
                        repo.git.add(".")
                        # Commit changes with a message
                        repo.git.commit(m="Auto-commit of local changes before pull")
                        logger.info("Successfully committed local changes")

                    # Now pull latest changes
                    logger.info("Pulling latest changes")
                    origin = repo.remote("origin")
                    try:
                        origin.pull()
                        logger.info("Successfully updated midi-presets repository")
                    except GitCommandError as e:
                        # If pull fails with rebase conflicts, try to continue the rebase
                        if "You have unstaged changes" in str(
                            e
                        ) or "cannot pull with rebase" in str(e):
                            logger.warning(
                                f"Pull failed due to rebase conflicts: {str(e)}"
                            )
                            # Try to stash changes and then pull
                            repo.git.stash()
                            logger.info("Stashed changes")
                            origin.pull()
                            # Apply stash if needed
                            repo.git.stash("pop")
                            logger.info("Applied stashed changes")
                        else:
                            # Re-raise other git errors
                            raise

                return True, "midi-presets repository ready", 200

            except git.InvalidGitRepositoryError:
                logger.warning(
                    "Directory exists but is not a git repository, removing and cloning fresh"
                )
                shutil.rmtree(midi_presets_dir)

        # Clone the repository
        if not os.path.exists(midi_presets_dir):
            logger.info(f"Cloning {midi_presets_url} to {midi_presets_dir}")
            Repo.clone_from(midi_presets_url, midi_presets_dir)
            logger.info("Successfully cloned midi-presets repository")

        return True, "midi-presets repository cloned successfully", 200

    except Exception as e:
        error_msg = f"Error ensuring midi-presets clone: {str(e)}"
        logger.error(error_msg)
        return False, error_msg, 500


def ensure_midi_presets_submodule():
    """
    Ensure midi-presets exists as a git submodule (for dev mode)

    Returns:
        Tuple of (success: bool, message: str, status_code: int)
    """
    logger.info("Ensuring midi-presets exists as a git submodule")

    try:
        # Get the server directory and project root
        server_dir = os.path.dirname(__file__)
        project_root = os.path.dirname(server_dir)
        midi_presets_dir = os.path.join(server_dir, "midi-presets")

        # Open the repository
        try:
            repo = Repo(project_root)
        except git.InvalidGitRepositoryError:
            error_msg = f"Not a valid git repository: {project_root}"
            logger.error(error_msg)
            return False, error_msg, 500

        # Check if .gitmodules exists and has our submodule
        gitmodules_path = os.path.join(project_root, ".gitmodules")
        has_submodule_config = False

        if os.path.exists(gitmodules_path):
            with open(gitmodules_path, "r") as f:
                content = f.read()
                if "server/midi-presets" in content:
                    has_submodule_config = True

        # If submodule is not configured, add it
        if not has_submodule_config:
            logger.info("Submodule not configured, adding it")

            # Remove existing directory if it exists
            if os.path.exists(midi_presets_dir):
                shutil.rmtree(midi_presets_dir)

            # Add submodule
            repo.git.submodule(
                "add",
                "https://github.com/tirans/midi-presets.git",
                "server/midi-presets",
            )
            logger.info("Added midi-presets as submodule")

        # Update submodule
        repo.git.submodule("update", "--init", "--recursive")
        logger.info("Successfully updated midi-presets submodule")

        return True, "midi-presets submodule ready", 200

    except Exception as e:
        error_msg = f"Error ensuring midi-presets submodule: {str(e)}"
        logger.error(error_msg)
        return False, error_msg, 500


def git_sync():
    """
    Sync midi-presets based on R2MIDI_ROLE environment variable

    - If R2MIDI_ROLE is 'dev': Use submodule approach
    - Otherwise (including 'release' or unset): Use clone approach

    Returns:
        Tuple of (success: bool, message: str, status_code: int)
    """
    mode = get_midi_presets_mode()

    if mode == "submodule":
        # Development mode - use the existing submodule sync logic
        return git_sync_submodule()
    else:
        # Release mode - ensure it's a regular clone
        return ensure_midi_presets_clone()


def git_remote_sync():
    """
    Add, commit, and push changes to the midi-presets repository

    This function:
    1. Determines the mode (submodule or clone) based on R2MIDI_ROLE
    2. Adds all changes with git add .
    3. Commits the changes with the message "new presets"
    4. Pushes the changes to the remote repository
    5. If in submodule mode, updates the submodule reference in the parent repository

    Returns:
        Tuple of (success: bool, message: str, status_code: int)
    """
    import os
    import traceback

    # Get the current directory to return to it later
    current_dir = os.getcwd()
    logger = logging.getLogger(__name__)
    logger.info(f"Starting git remote sync from directory: {current_dir}")

    try:
        # Determine the mode (submodule or clone)
        mode = get_midi_presets_mode()
        logger.info(f"Git remote sync mode: {mode}")

        # Get the server directory (where this file is located)
        server_dir = os.path.dirname(__file__)
        # Get the project root directory (parent of server)
        project_root = os.path.dirname(server_dir)
        midi_presets_dir = os.path.join(server_dir, "midi-presets")

        # Check if the midi-presets directory exists
        if not os.path.exists(midi_presets_dir):
            error_msg = f"Midi-presets directory not found at {midi_presets_dir}"
            logger.error(error_msg)
            return False, error_msg, 404

        # Check if it's a directory
        if not os.path.isdir(midi_presets_dir):
            error_msg = f"Path exists but is not a directory: {midi_presets_dir}"
            logger.error(error_msg)
            return False, error_msg, 400

        # Change to the midi-presets directory
        os.chdir(midi_presets_dir)
        logger.info(f"Successfully changed directory to {midi_presets_dir}")

        # Check if it's a git repository
        try:
            # Open the repository
            repo = Repo(midi_presets_dir)
            logger.info(f"Git repository check: True")
        except git.InvalidGitRepositoryError:
            error_msg = f"Not a git repository: {midi_presets_dir}"
            logger.error(error_msg)
            os.chdir(current_dir)  # Return to the original directory
            return False, error_msg, 400

        try:
            # Log git status before making changes
            logger.info("Checking git status before making changes...")
            pre_status = repo.git.status()
            logger.info(f"Git status before changes:\n{pre_status}")

            # Add all changes
            logger.info("Adding all changes in midi-presets...")
            add_output = repo.git.add(".")
            logger.info(f"Git add output: {add_output if add_output else 'No output'}")

            # Check if there are changes to commit
            logger.info("Checking if there are changes to commit...")
            status_output = repo.git.status(porcelain=True)
            logger.info(f"Git status output: {status_output}")

            if not status_output.strip():
                logger.info("No changes to commit in midi-presets")
                os.chdir(current_dir)  # Return to the original directory
                return True, "No changes to commit in midi-presets", 200

            # Commit changes
            logger.info("Committing changes in midi-presets...")
            commit_output = repo.git.commit(m="new presets")
            logger.info(f"Git commit output: {commit_output}")

            # Push changes
            logger.info("Pushing changes in midi-presets...")
            push_output = repo.git.push()
            logger.info(
                f"Git push output: {push_output if push_output else 'No output'}"
            )

            # Return to the original directory
            os.chdir(current_dir)
            logger.info(f"Returned to original directory: {current_dir}")

            # If in submodule mode, update the submodule reference in the parent repository
            if mode == "submodule":
                logger.info("Updating submodule reference in parent repository...")
                parent_repo = Repo(project_root)
                parent_add_output = parent_repo.git.add("server/midi-presets")
                logger.info(
                    f"Git add output: {parent_add_output if parent_add_output else 'No output'}"
                )

            logger.info("Git remote sync completed successfully")
            return (
                True,
                "Successfully added, committed, and pushed changes to midi-presets repository",
                200,
            )
        except GitCommandError as e:
            error_msg = f"Git remote sync failed: {e.stderr}"
            logger.error(error_msg)
            logger.error(f"Command: {e.command}")
            os.chdir(current_dir)  # Return to the original directory
            return False, error_msg, 500
        except Exception as e:
            error_msg = f"Error running git remote sync: {str(e)}"
            logger.error(error_msg)
            logger.error(f"Exception type: {type(e).__name__}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            os.chdir(current_dir)  # Return to the original directory
            return False, error_msg, 500
    except Exception as e:
        error_msg = f"Unexpected error in git_remote_sync: {str(e)}"
        logger.error(error_msg)
        logger.error(f"Exception type: {type(e).__name__}")
        logger.error(f"Traceback: {traceback.format_exc()}")

        # Try to return to the original directory
        try:
            os.chdir(current_dir)
            logger.info(f"Returned to original directory: {current_dir}")
        except Exception as chdir_error:
            logger.error(f"Error returning to original directory: {str(chdir_error)}")

        return False, error_msg, 500


def git_sync_submodule():
    """
    Original git submodule sync function (for dev mode)

    This function:
    1. Runs git submodule sync from the repository root
    2. Runs git submodule update --init --recursive to update the submodule
    3. If that fails, tries more aggressive approaches including complete removal and re-cloning
    4. Logs each step of the operation

    Returns:
        Tuple of (success: bool, message: str, status_code: int)
    """
    logger.info("Starting git submodule sync operation (dev mode)")

    try:
        # Get the server directory (where this file is located)
        server_dir = os.path.dirname(__file__)
        # Get the project root directory (parent of server)
        project_root = os.path.dirname(server_dir)
        midi_presets_dir = os.path.join(server_dir, "midi-presets")

        # Open the repository
        try:
            repo = Repo(project_root)
        except git.InvalidGitRepositoryError:
            error_msg = f"Not a valid git repository: {project_root}"
            logger.error(error_msg)
            return False, error_msg, 500

        # Step 1: Try the standard approach first
        try:
            logger.info("Step 1: Syncing git submodule...")

            # Check if the submodule directory exists and is a git repository
            if os.path.exists(midi_presets_dir):
                try:
                    # Try to open the submodule as a repository
                    submodule_repo = Repo(midi_presets_dir)

                    # Check for unstaged changes in the submodule
                    logger.info("Checking for unstaged changes in submodule...")
                    status_output = submodule_repo.git.status(porcelain=True)

                    if status_output.strip():
                        logger.info(
                            "Found unstaged changes in submodule, committing them before update"
                        )
                        # Save current directory
                        current_dir = os.getcwd()
                        try:
                            # Change to submodule directory
                            os.chdir(midi_presets_dir)

                            # Add all changes
                            submodule_repo.git.add(".")
                            # Commit changes with a message
                            submodule_repo.git.commit(
                                m="Auto-commit of local changes before submodule update"
                            )
                            logger.info(
                                "Successfully committed local changes in submodule"
                            )
                        finally:
                            # Return to original directory
                            os.chdir(current_dir)
                except (git.InvalidGitRepositoryError, Exception) as e:
                    logger.warning(f"Error checking submodule repository: {str(e)}")
                    # Continue with normal submodule update

            # Sync the submodule
            with repo.git.custom_environment(GIT_TERMINAL_PROMPT="0"):
                sync_output = repo.git.submodule("sync")
                logger.info(f"Git submodule sync output: {sync_output}")

                # Update the submodule
                logger.info("Updating git submodule...")
                try:
                    update_output = repo.git.submodule(
                        "update", "--init", "--recursive"
                    )
                    logger.info(f"Git submodule update output: {update_output}")
                except GitCommandError as e:
                    # If update fails with unstaged changes error, try to stash and update
                    if "You have unstaged changes" in str(
                        e
                    ) or "cannot pull with rebase" in str(e):
                        logger.warning(
                            f"Submodule update failed due to unstaged changes: {str(e)}"
                        )

                        # Try to stash changes in the submodule
                        current_dir = os.getcwd()
                        try:
                            # Change to submodule directory
                            os.chdir(midi_presets_dir)

                            # Stash changes
                            submodule_repo = Repo(midi_presets_dir)
                            submodule_repo.git.stash()
                            logger.info("Stashed changes in submodule")

                            # Return to original directory and retry update
                            os.chdir(current_dir)
                            update_output = repo.git.submodule(
                                "update", "--init", "--recursive"
                            )
                            logger.info(
                                f"Git submodule update output after stashing: {update_output}"
                            )

                            # Apply stash if needed
                            os.chdir(midi_presets_dir)
                            submodule_repo.git.stash("pop")
                            logger.info("Applied stashed changes in submodule")
                        finally:
                            # Ensure we return to original directory
                            os.chdir(current_dir)
                    else:
                        # Re-raise other git errors
                        raise

            # If we get here, it worked!
            logger.info(
                "Git submodule sync completed successfully with standard approach"
            )
            return True, "Git submodule sync completed successfully", 200

        except GitCommandError as e:
            logger.warning(f"Standard submodule update failed: {e.stderr}")
            # Continue to next approach

        # Step 2: Try with force flag
        try:
            logger.info("Step 2: Trying submodule update with force...")

            # Reset the submodule state
            with repo.git.custom_environment(GIT_TERMINAL_PROMPT="0"):
                reset_output = repo.git.submodule(
                    "deinit", "-f", "--", "server/midi-presets"
                )
                logger.info(f"Git submodule deinit output: {reset_output}")

                # Re-initialize and update with force
                reinit_output = repo.git.submodule(
                    "update", "--init", "--recursive", "--force"
                )
                logger.info(f"Git submodule force update output: {reinit_output}")

            # If we get here, it worked!
            logger.info("Git submodule sync completed successfully with force approach")
            return True, "Git submodule sync completed successfully", 200

        except GitCommandError as e:
            logger.warning(f"Force submodule update failed: {e.stderr}")
            # Continue to next approach

        # Step 3: Most aggressive approach - remove and re-clone
        logger.info("Step 3: Trying complete removal and re-initialization...")

        # First, get the submodule URL from .gitmodules
        try:
            # Get the submodule URL from the repo's configuration
            try:
                # Check if the submodule is configured
                submodule_url = None
                for submodule in repo.submodules:
                    if submodule.name == "server/midi-presets":
                        submodule_url = submodule.url
                        break

                # If not found in submodules, try to get it from .gitmodules file
                if not submodule_url:
                    gitmodules_path = os.path.join(project_root, ".gitmodules")
                    if not os.path.exists(gitmodules_path):
                        raise FileNotFoundError(
                            f".gitmodules file not found at {gitmodules_path}"
                        )

                    # Parse .gitmodules to get the URL
                    with open(gitmodules_path, "r") as f:
                        content = f.read()
                        url_match = re.search(
                            r'\[submodule\s+"server/midi-presets"\].*?\s+url\s+=\s+(.+)',
                            content,
                            re.DOTALL,
                        )
                        if url_match:
                            submodule_url = url_match.group(1).strip()

                if not submodule_url:
                    # Use the default URL if not found
                    submodule_url = "https://github.com/tirans/midi-presets.git"
                    logger.warning(
                        f"Could not find midi-presets URL in configuration, using default: {submodule_url}"
                    )
                else:
                    logger.info(f"Found submodule URL: {submodule_url}")

                # Verify that the URL is the expected one
                expected_url = "https://github.com/tirans/midi-presets.git"
                if submodule_url != expected_url:
                    logger.warning(
                        f"Submodule URL {submodule_url} doesn't match expected URL {expected_url}"
                    )
                    submodule_url = expected_url
                    logger.info(f"Using expected URL: {submodule_url}")

            except Exception as e:
                logger.warning(
                    f"Error getting submodule URL from configuration: {str(e)}"
                )
                # Use the default URL if there was an error
                submodule_url = "https://github.com/tirans/midi-presets.git"
                logger.info(f"Using default submodule URL: {submodule_url}")

            # Check if the midi-presets directory exists
            if os.path.exists(midi_presets_dir):
                logger.info(f"Midi-presets directory exists at: {midi_presets_dir}")

                # Check if it's a regular git repository (not a submodule)
                git_dir = os.path.join(midi_presets_dir, ".git")
                if os.path.exists(git_dir) and os.path.isdir(git_dir):
                    logger.info(
                        "Detected regular git repository instead of submodule. Converting to submodule..."
                    )

                    # Get the current commit hash to preserve it
                    try:
                        midi_repo = Repo(midi_presets_dir)
                        current_commit = midi_repo.head.commit.hexsha
                        logger.info(f"Current commit hash: {current_commit}")
                    except Exception as e:
                        logger.warning(f"Could not get current commit hash: {str(e)}")
                        current_commit = None

                    # Remove the directory but preserve the content
                    temp_dir = os.path.join(project_root, "midi-presets-temp")
                    try:
                        # Create a temporary directory
                        if os.path.exists(temp_dir):
                            shutil.rmtree(temp_dir)

                        # Copy the content to the temporary directory
                        shutil.copytree(midi_presets_dir, temp_dir, symlinks=True)
                        logger.info(
                            f"Copied midi-presets content to temporary directory: {temp_dir}"
                        )

                        # Remove the original directory
                        shutil.rmtree(midi_presets_dir)
                        logger.info("Successfully removed midi-presets directory")

                        # After removing the directory, we'll let the submodule init/update recreate it
                        # and then we'll restore any local changes if needed
                    except Exception as e:
                        logger.warning(f"Error during directory operations: {str(e)}")
                        # If we failed to copy/remove, try the old approach
                        try:
                            # First try git clean to remove untracked files
                            repo.git.clean("-ffdx", "--", "server/midi-presets")
                        except Exception as e:
                            logger.warning(
                                f"Git clean failed, will try manual removal: {str(e)}"
                            )

                        # Then try to remove the directory manually
                        try:
                            shutil.rmtree(midi_presets_dir)
                            logger.info("Successfully removed midi-presets directory")
                        except Exception as e:
                            logger.warning(f"Error removing directory: {str(e)}")
                            # Try with os.system as a last resort
                            if os.path.exists(midi_presets_dir):
                                if os.name == "nt":  # Windows
                                    os.system(f'rmdir /S /Q "{midi_presets_dir}"')
                                else:  # Unix/Linux/MacOS
                                    os.system(f'rm -rf "{midi_presets_dir}"')
                                logger.info(
                                    "Used system command to remove midi-presets directory"
                                )
                else:
                    # It's not a regular git repository, so just remove it
                    logger.info("Removing existing midi-presets directory...")
                    try:
                        # First try git clean to remove untracked files
                        repo.git.clean("-ffdx", "--", "server/midi-presets")
                    except Exception as e:
                        logger.warning(
                            f"Git clean failed, will try manual removal: {str(e)}"
                        )

                    # Then try to remove the directory manually
                    try:
                        shutil.rmtree(midi_presets_dir)
                        logger.info("Successfully removed midi-presets directory")
                    except Exception as e:
                        logger.warning(f"Error removing directory: {str(e)}")
                        # Try with os.system as a last resort
                        if os.path.exists(midi_presets_dir):
                            if os.name == "nt":  # Windows
                                os.system(f'rmdir /S /Q "{midi_presets_dir}"')
                            else:  # Unix/Linux/MacOS
                                os.system(f'rm -rf "{midi_presets_dir}"')
                            logger.info(
                                "Used system command to remove midi-presets directory"
                            )

            # Remove from git's index
            try:
                repo.git.rm("-f", "--cached", "server/midi-presets")
                logger.info("Removed midi-presets from git index")
            except Exception as e:
                logger.warning(f"Error removing from git index: {str(e)}")

            # Re-initialize the submodule
            logger.info("Re-initializing the submodule...")
            with repo.git.custom_environment(GIT_TERMINAL_PROMPT="0"):
                init_output = repo.git.submodule("init")
                logger.info(f"Git submodule init output: {init_output}")

                # Clone the submodule
                logger.info(f"Cloning the submodule from {submodule_url}...")
                clone_output = repo.git.submodule("update", "--init", "--recursive")
                logger.info(f"Git submodule clone output: {clone_output}")

            # Verify the submodule was cloned successfully
            if os.path.exists(midi_presets_dir) and os.path.isdir(midi_presets_dir):
                logger.info(
                    "Git submodule sync completed successfully with complete re-initialization"
                )

                # Check if we have a temporary directory with content to restore
                temp_dir = os.path.join(project_root, "midi-presets-temp")
                if os.path.exists(temp_dir) and os.path.isdir(temp_dir):
                    try:
                        # Copy any files that don't exist in the submodule
                        for root, dirs, files in os.walk(temp_dir):
                            rel_path = os.path.relpath(root, temp_dir)
                            target_dir = os.path.join(midi_presets_dir, rel_path)

                            # Create target directory if it doesn't exist
                            if not os.path.exists(target_dir):
                                os.makedirs(target_dir, exist_ok=True)

                            # Copy files
                            for file in files:
                                source_file = os.path.join(root, file)
                                target_file = os.path.join(target_dir, file)

                                # Only copy if the file doesn't exist or is different
                                if not os.path.exists(target_file):
                                    shutil.copy2(source_file, target_file)

                        logger.info("Restored content from temporary directory")

                        # Clean up the temporary directory
                        shutil.rmtree(temp_dir)
                        logger.info("Removed temporary directory")
                    except Exception as e:
                        logger.warning(
                            f"Error restoring content from temporary directory: {str(e)}"
                        )

                return (
                    True,
                    "Git submodule sync completed successfully with complete re-initialization",
                    200,
                )
            else:
                raise Exception(
                    f"Submodule directory not found after re-initialization: {midi_presets_dir}"
                )

        except Exception as e:
            logger.error(f"Complete re-initialization failed: {str(e)}")
            return False, f"All git sync approaches failed. Last error: {str(e)}", 500

    except GitCommandError as e:
        error_msg = f"Git operation failed: {e.stderr}"
        logger.error(error_msg)
        return False, error_msg, 500
    except Exception as e:
        error_msg = f"Error during git submodule sync: {str(e)}"
        logger.error(error_msg)
        return False, error_msg, 500
