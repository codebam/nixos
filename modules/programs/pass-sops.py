import os
import sys
import subprocess
import yaml
import secrets
import string
import getpass
import tempfile
from urllib.parse import urlparse, parse_qs

# Ensure SOPS_AGE_KEY_FILE is set if key files exist
if "SOPS_AGE_KEY_FILE" not in os.environ:
    for key_path in [
        "/etc/nixos/secrets/identities/yubikey-5c.txt",
        "/etc/nixos/secrets/identities/yubikey-5c-nfc.txt",
        "/persistent/var/lib/sops-nix/key.txt",
        "/var/lib/sops-nix/key.txt"
    ]:
        if os.path.exists(key_path) and os.access(key_path, os.R_OK):
            os.environ["SOPS_AGE_KEY_FILE"] = key_path
            break

SOPS_FILE = "/etc/nixos/secrets/passwords.enc.yaml"

def load_passwords():
    if not os.path.exists(SOPS_FILE):
        return {}
    try:
        res = subprocess.run(["sops", "-d", SOPS_FILE], capture_output=True, text=True, check=True)
        return yaml.safe_load(res.stdout) or {}
    except subprocess.CalledProcessError as e:
        print(f"Error decrypting passwords: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error loading YAML: {e}", file=sys.stderr)
        sys.exit(1)

def save_passwords(data):
    try:
        # Write unencrypted first, then encrypt in place
        with open(SOPS_FILE, "w") as f:
            yaml.dump(data, f, default_flow_style=False, allow_unicode=True)
        subprocess.run(["sops", "--encrypt", "--in-place", SOPS_FILE], check=True)
    except Exception as e:
        print(f"Error saving passwords: {e}", file=sys.stderr)
        sys.exit(1)

def get_key(d, path_parts):
    curr = d
    for p in path_parts:
        if not isinstance(curr, dict) or p not in curr:
            return None
        curr = curr[p]
    return curr

def set_key(d, path_parts, value):
    curr = d
    for p in path_parts[:-1]:
        curr = curr.setdefault(p, {})
    curr[path_parts[-1]] = value

def delete_key(d, path_parts):
    def rec_delete(curr, parts):
        if not parts:
            return True
        p = parts[0]
        if p not in curr:
            return False
        if len(parts) == 1:
            del curr[p]
            return len(curr) == 0
        else:
            should_delete_parent = rec_delete(curr[p], parts[1:])
            if should_delete_parent:
                del curr[p]
            return len(curr) == 0
    rec_delete(d, path_parts)

def print_tree(d, prefix=""):
    if not isinstance(d, dict):
        return
    keys = sorted(d.keys())
    for i, k in enumerate(keys):
        is_last = (i == len(keys) - 1)
        connector = "└── " if is_last else "├── "
        print(f"{prefix}{connector}{k}")
        next_prefix = prefix + ("    " if is_last else "│   ")
        if isinstance(d[k], dict):
            print_tree(d[k], next_prefix)

def copy_to_clipboard(text):
    # Strip trailing newline for clipboard comfort
    text_to_copy = text.splitlines()[0] if text.splitlines() else ""
    for cmd in [["wl-copy"], ["xclip", "-selection", "clipboard"], ["xsel", "--clipboard", "--input"]]:
        try:
            subprocess.run(cmd, input=text_to_copy, text=True, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            print("Copied first line of password to clipboard.")
            return True
        except Exception:
            continue
    print("Failed to copy to clipboard (wl-copy/xclip not available).", file=sys.stderr)
    return False

def show_command(path, clip=False):
    data = load_passwords()
    if not path:
        print("Password Store")
        print_tree(data)
        return
    
    parts = path.strip("/").split("/")
    val = get_key(data, parts)
    if val is None:
        print(f"Error: {path} is not in the password store.", file=sys.stderr)
        sys.exit(1)
        
    if isinstance(val, dict):
        print(path)
        print_tree(val)
    else:
        if clip:
            copy_to_clipboard(val)
        else:
            sys.stdout.write(val)
            if not val.endswith("\n"):
                sys.stdout.write("\n")

def insert_command(path, multiline=False, force=False):
    data = load_passwords()
    parts = path.strip("/").split("/")
    
    if get_key(data, parts) is not None and not force:
        ans = input(f"An entry already exists for {path}. Overwrite it? [y/N] ")
        if ans.lower() not in ["y", "yes"]:
            print("Cancelled.")
            return

    if multiline:
        print("Enter contents of password (Ctrl-D or Ctrl-Z to finish):")
        val = sys.stdin.read()
    else:
        p1 = getpass.getpass(f"Enter password for {path}: ")
        p2 = getpass.getpass(f"Retype password for {path}: ")
        if p1 != p2:
            print("Error: Passwords do not match.", file=sys.stderr)
            sys.exit(1)
        val = p1
        
    set_key(data, parts, val)
    save_passwords(data)
    print(f"Inserted entry for {path}")

def generate_command(path, length=25, no_symbols=False, clip=False, force=False):
    data = load_passwords()
    parts = path.strip("/").split("/")
    
    if get_key(data, parts) is not None and not force:
        ans = input(f"An entry already exists for {path}. Overwrite it? [y/N] ")
        if ans.lower() not in ["y", "yes"]:
            print("Cancelled.")
            return

    chars = string.ascii_letters + string.digits
    if not no_symbols:
        chars += "!@#$%^&*()-_=+[]{}|;:,.<>?"
    password = "".join(secrets.choice(chars) for _ in range(length))
    
    set_key(data, parts, password)
    save_passwords(data)
    print(f"Generated password for {path}")
    if clip:
        copy_to_clipboard(password)
    else:
        print(password)

def rm_command(path, recursive=False, force=False):
    data = load_passwords()
    parts = path.strip("/").split("/")
    val = get_key(data, parts)
    
    if val is None:
        print(f"Error: {path} is not in the password store.", file=sys.stderr)
        sys.exit(1)
        
    if isinstance(val, dict) and not recursive:
        print(f"Error: {path} is a directory. Use recursive option to remove.", file=sys.stderr)
        sys.exit(1)
        
    if not force:
        ans = input(f"Are you sure you want to delete {path}? [y/N] ")
        if ans.lower() not in ["y", "yes"]:
            print("Cancelled.")
            return
            
    delete_key(data, parts)
    save_passwords(data)
    print(f"Removed {path}")

def edit_command(path):
    data = load_passwords()
    parts = path.strip("/").split("/")
    val = get_key(data, parts)
    
    if isinstance(val, dict):
        print(f"Error: {path} is a directory.", file=sys.stderr)
        sys.exit(1)
        
    initial_content = val if val is not None else ""
    
    editor = os.environ.get("EDITOR", "hx")
    with tempfile.NamedTemporaryFile(suffix=".tmp", mode="w+", delete=False) as tf:
        tf.write(initial_content)
        temp_name = tf.name
        
    try:
        subprocess.run([editor, temp_name], check=True)
        with open(temp_name, "r") as tf:
            new_content = tf.read()
        if new_content != initial_content:
            set_key(data, parts, new_content)
            save_passwords(data)
            print(f"Updated {path}")
        else:
            print("No changes made.")
    finally:
        if os.path.exists(temp_name):
            os.remove(temp_name)

def otp_command(path):
    import pyotp
    data = load_passwords()
    parts = path.strip("/").split("/")
    val = get_key(data, parts)
    
    if val is None:
        print(f"Error: {path} is not in the password store.", file=sys.stderr)
        sys.exit(1)
        
    if isinstance(val, dict):
        print(f"Error: {path} is a directory.", file=sys.stderr)
        sys.exit(1)
        
    # Search lines for otpauth://
    for line in val.splitlines():
        if line.strip().startswith("otpauth://"):
            url = urlparse(line.strip())
            query = parse_qs(url.query)
            secret = query.get("secret")
            if secret:
                secret_str = secret[0].replace(" ", "").upper()
                try:
                    totp = pyotp.TOTP(secret_str)
                    print(totp.now())
                    return
                except Exception as e:
                    print(f"Error generating TOTP: {e}", file=sys.stderr)
                    sys.exit(1)
    print("Error: No OTP secret found in this entry.", file=sys.stderr)
    sys.exit(1)

def print_help():
    help_text = """sops-pass: A pass (password-store) migration wrapper using SOPS
Usage:
    pass [show] [-c|--clip] [path]
        Show or copy a password.
    pass insert [-m|--multiline] [-f|--force] [path]
        Insert a new password.
    pass generate [-n|--no-symbols] [-c|--clip] [-f|--force] [path] [length]
        Generate a random password.
    pass rm [-f|--force] [-r|--recursive] [path]
        Remove a password or directory.
    pass edit [path]
        Edit a password using $EDITOR.
    pass otp [path]
        Generate a TOTP token if the entry contains an otpauth:// URI.
    pass ls|list [path]
        List passwords.
"""
    print(help_text)

def main():
    args = sys.argv[1:]
    if not args:
        show_command("")
        return
        
    cmd = args[0]
    
    if cmd in ["-h", "--help", "help"]:
        print_help()
        return

    # Default to show if first arg is not a known command
    if cmd not in ["show", "insert", "generate", "rm", "remove", "edit", "otp", "ls", "list"]:
        # Check if first arg starts with "-"
        if cmd.startswith("-"):
            # Could be flags for show
            clip = "-c" in args or "--clip" in args
            path = ""
            for a in args:
                if not a.startswith("-"):
                    path = a
                    break
            show_command(path, clip=clip)
        else:
            show_command(cmd)
        return

    if cmd in ["show"]:
        clip = "-c" in args or "--clip" in args
        path = ""
        for a in args[1:]:
            if not a.startswith("-"):
                path = a
                break
        show_command(path, clip=clip)
        
    elif cmd in ["ls", "list"]:
        path = args[1] if len(args) > 1 else ""
        show_command(path)
        
    elif cmd in ["insert"]:
        multiline = "-m" in args or "--multiline" in args
        force = "-f" in args or "--force" in args
        path = ""
        for a in args[1:]:
            if not a.startswith("-"):
                path = a
                break
        if not path:
            print("Error: path required.", file=sys.stderr)
            sys.exit(1)
        insert_command(path, multiline=multiline, force=force)
        
    elif cmd in ["generate"]:
        no_symbols = "-n" in args or "--no-symbols" in args
        clip = "-c" in args or "--clip" in args
        force = "-f" in args or "--force" in args
        path = ""
        length = 25
        non_flags = [a for a in args[1:] if not a.startswith("-")]
        if not non_flags:
            print("Error: path required.", file=sys.stderr)
            sys.exit(1)
        path = non_flags[0]
        if len(non_flags) > 1:
            try:
                length = int(non_flags[1])
            except ValueError:
                pass
        generate_command(path, length=length, no_symbols=no_symbols, clip=clip, force=force)
        
    elif cmd in ["rm", "remove"]:
        recursive = "-r" in args or "--recursive" in args
        force = "-f" in args or "--force" in args
        path = ""
        for a in args[1:]:
            if not a.startswith("-"):
                path = a
                break
        if not path:
            print("Error: path required.", file=sys.stderr)
            sys.exit(1)
        rm_command(path, recursive=recursive, force=force)
        
    elif cmd in ["edit"]:
        if len(args) < 2:
            print("Error: path required.", file=sys.stderr)
            sys.exit(1)
        edit_command(args[1])
        
    elif cmd in ["otp"]:
        if len(args) < 2:
            print("Error: path required.", file=sys.stderr)
            sys.exit(1)
        otp_command(args[1])

if __name__ == "__main__":
    main()
