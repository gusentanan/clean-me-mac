PRESET_NAME="unzip-extracts"
PRESET_DESC="Extracted archives kept inside the UnzipAnyFile app container"
# Extractions are stored in 32-hex-char folders; the symlinks that share the
# directory (AddressBook, iCloud, ...) don't match this pattern.
_hex32=$(printf '[0-9A-F]%.0s' {1..32})
PRESET_PATHS=("$HOME/Library/Containers/com.Ababe.UnzipAnyFile/Data/Library/Application Support/$_hex32")
unset _hex32
PRESET_SAFE=false
